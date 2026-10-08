# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées sur l'hôte distant
# _m09-operationnel.sh — fonctions partagées par les checks M09-E10 à M09-E23 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m09o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès utilisés (tous en lecture) :
#   - les nœuds en root par leurs alias SSH hv01, hv02, hv03 (~/.ssh/config de adm01, M09-E03) :
#     pvesh get, ceph … (lecture), ha-manager status, pvesr status, zfs list, vtysh -c 'show …' ;
#   - ceph01 (WB_CEPH_ADMIN, M08) en sudo -n, pour M09-E12 seulement ;
#   - pbs01 en root (WB_PBS_HOST), pour M09-E15 (ACL en lecture) ;
#   - l'API GitLab (jeton des checks), DNS du lab, port 8006 de la VIP (sans authentification).

_M09O_NOEUDS="hv01 hv02 hv03"
_M09O_PBS="${WB_PBS_HOST:-pbs01}"
_M09O_CEPH="${WB_CEPH_ADMIN:-ceph01}"
_M09O_DNS="10.10.20.10"

# _m09o_hv NŒUD COMMANDE — commande en root sur un nœud ; sortie vide si le nœud ne répond pas.
_m09o_hv() {
  remote "$1" "$2" 2>/dev/null || true
}

# _m09o_noeud — premier nœud joignable (mis en cache dans _M09O_N ; vide si aucun).
_M09O_N=""
_m09o_noeud() {
  local n
  if [[ -z "$_M09O_N" ]]; then
    for n in $_M09O_NOEUDS; do
      if remote "$n" true >/dev/null 2>&1; then _M09O_N="$n"; break; fi
    done
  fi
  echo "$_M09O_N"
}

# _m09o_pvesh CHEMIN [OPTIONS…] — « pvesh get » en JSON sur le premier nœud joignable.
_m09o_pvesh() {
  local n chemin="$1"
  shift
  n="$(_m09o_noeud)"
  [[ -n "$n" ]] || return 0
  _m09o_hv "$n" "pvesh get $chemin $* --output-format json"
}

# _m09o_ceph ARGUMENTS — commande « ceph » (lecture, sortie JSON) sur le premier nœud joignable.
_m09o_ceph() {
  local n
  n="$(_m09o_noeud)"
  [[ -n "$n" ]] || return 0
  _m09o_hv "$n" "timeout 20 ceph $1 --format json"
}

# _m09o_json JSON FILTRE [ARGS jq…] — vrai si le filtre jq (-e) est vrai sur le JSON donné.
_m09o_json() {
  local donnees="$1" filtre="$2"
  shift 2
  [[ -n "$donnees" ]] && jq -e "$@" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m09o_conf VMID — configuration courante (avant la première section d'instantané) d'un invité
# imbriqué, lue dans pmxcfs quel que soit son nœud ; vide si l'invité n'existe pas.
_m09o_conf() {
  local n
  n="$(_m09o_noeud)"
  [[ -n "$n" ]] || return 0
  _m09o_hv "$n" "f=\$(ls /etc/pve/nodes/*/qemu-server/$1.conf 2>/dev/null | head -n 1); [ -n \"\$f\" ] && sed '/^\[/q' \"\$f\" | grep -v '^\['"
}

# _m09o_disques CONF — lignes de disques (hors lecteurs CD et cloud-init) de la configuration.
_m09o_disques() {
  grep -E '^(scsi|virtio|sata|ide|efidisk|tpmstate)[0-9]+: ' <<<"$1" | grep -v 'media=cdrom' | grep -v 'cloudinit' || true
}

# _m09o_disques_sur CONF STOCKAGE — la VM a au moins un disque, et tous sont sur STOCKAGE.
_m09o_disques_sur() {
  local d
  d="$(_m09o_disques "$1")"
  [[ -n "$d" ]] && ! grep -qv -- ": $2:" <<<"$d"
}

# _m09o_ressources — /cluster/resources (type vm) en JSON.
_m09o_ressources() {
  _m09o_pvesh /cluster/resources --type vm
}

# _m09o_vm_existe RESSOURCES VMID — l'invité figure dans /cluster/resources.
_m09o_vm_existe() {
  _m09o_json "$1" 'map(select(.vmid == $id)) | length == 1' --argjson id "$2"
}

# _m09o_stockage_cfg ID — section « type: ID » de /etc/pve/storage.cfg (vide si absente).
_m09o_stockage_cfg() {
  local n
  n="$(_m09o_noeud)"
  [[ -n "$n" ]] || return 0
  _m09o_hv "$n" "awk -v id='$1' '/^[a-z]+: / {garde = (\$2 == id)} garde' /etc/pve/storage.cfg"
}

# _m09o_stockage_actif_partout ID — le stockage est actif sur les trois nœuds.
_m09o_stockage_actif_partout() {
  local n
  for n in $_M09O_NOEUDS; do
    _m09o_hv "$n" "pvesm status --storage $1 2>/dev/null" | grep -Eq "^$1[[:space:]]+[a-z]+[[:space:]]+active" || return 1
  done
}

# _m09o_fichier_main PROJET CHEMIN — le fichier existe sur main du projet GitLab (« plateforme/x »).
_m09o_fichier_main() {
  local p c
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  c="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/files/$c?ref=main" >/dev/null 2>&1
}

# _m09o_contenu_main PROJET CHEMIN — contenu brut d'un fichier de main (vide si absent).
_m09o_contenu_main() {
  local p c
  p="$(jq -rn --arg v "$1" '$v | @uri')"
  c="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "projects/$p/repository/files/$c/raw?ref=main" 2>/dev/null || true
}

# _m09o_ha_ressources — /cluster/ha/resources en JSON.
_m09o_ha_ressources() {
  _m09o_pvesh /cluster/ha/resources
}

# _m09o_ha_etat — /cluster/ha/status/current en JSON (quorum, maître, LRM, services).
_m09o_ha_etat() {
  _m09o_pvesh /cluster/ha/status/current
}

# _m09o_aucun_injoignable — les trois nœuds répondent en SSH (sinon les contrôles « partout »
# n'auraient pas de sens : on le dit une fois, clairement).
_m09o_tous_joignables() {
  local n
  for n in $_M09O_NOEUDS; do
    remote "$n" true >/dev/null 2>&1 || return 1
  done
}
