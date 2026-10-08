# shellcheck shell=bash
# _m09-commun.sh — fonctions partagées par les scripts de panne du module 09 (M09-E35 à M09-E43).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (_WB_PRELUDE, _wb_entete, wb_avert, WB_EX…).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Périmètre (PLAN §4.9, « Pannes du bloc B ») : les pannes n'agissent QUE dans les nœuds imbriqués
# hv01-03 (VMs 2091-2093 du pool lab) et sur les invités imbriqués 191-197 qu'elles créent elles-mêmes.
# Jamais sur pve01 (ni son réseau, ni son pare-feu), jamais sur pbs01 (QDevice compris), jamais sur
# l'iLO de hp01. Aucune variante ne coupe l'accès SSH de adm01 (10.10.10.10) aux nœuds.
#
# 1. Accès : alias SSH hv01…hv03 de ~/.ssh/config sur adm01 (HostName = IP MGMT, User root, M09-E03),
#    avec la clé de adm01 installée par le fichier de réponse de l'installateur automatique ; pas de sudo sur un nœud Proxmox VE. m09_exec envoie le
#    prélude de pannes-lib.sh (journal, sauver…) puis _M09_AIDE_DISTANTE, puis le script.
# 2. Aide distante : sauvegarde de fichiers entiers (y compris dans /etc/pve, où « cp -a » échoue :
#    pmxcfs impose propriétaire et droits), empreinte de l'état posé, restauration seulement si le
#    fichier est encore dans l'état posé (sinon : réparation de l'apprenant, laissée telle quelle) ;
#    table nftables dédiée « inet infoger_durcissement » (créée et retirée en bloc).
# 3. HA : les pannes qui font perdre le quorum à un nœud qui porte des ressources HA désarment d'abord
#    la pile HA (ha-manager crm-command disarm-ha freeze, Proxmox VE 9.2), sinon le nœud se clôturerait
#    (fencing par watchdog, 60 s) et le redémarrage effacerait la panne. Le réarmement (arm-ha) est fait
#    à l'annulation, seulement si c'est la panne qui a désarmé.
# 4. Invités imbriqués de test : VMID 191-197 réservés aux pannes du palier 4 (étiquette pannes-m09),
#    créés et détruits par les scripts, sans système d'exploitation (un disque vide suffit).
# 5. m09_essayer : variantes sans effet sur un lab donné → on passe à la suivante (comme au M06).

_M09_NOEUDS=(hv01 hv02 hv03)
# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
declare -A _M09_IP=([hv01]=10.10.10.51 [hv02]=10.10.10.52 [hv03]=10.10.10.53)
# shellcheck disable=SC2034
declare -A _M09_CORO=([hv01]=10.10.32.51 [hv02]=10.10.32.52 [hv03]=10.10.32.53)
# shellcheck disable=SC2034
declare -A _M09_STOPUB=([hv01]=10.10.30.71 [hv02]=10.10.30.72 [hv03]=10.10.30.73)
# shellcheck disable=SC2034
declare -A _M09_STOCLU=([hv01]=10.10.31.71 [hv02]=10.10.31.72 [hv03]=10.10.31.73)
# shellcheck disable=SC2034
declare -A _M09_VMID=([hv01]=2091 [hv02]=2092 [hv03]=2093)
# shellcheck disable=SC2034
_M09_VIP=10.10.10.200
# shellcheck disable=SC2034
_M09_TABLE=infoger_durcissement

# ---------------------------------------------------------------------------
# État local (adm01)
# ---------------------------------------------------------------------------

# m09_etat EXX — dossier d'état local de la panne (créé en 700).
m09_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M09-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}

# m09_journal EXX "message" — journal local de la panne.
m09_journal() {
  local ex="$1" d
  shift
  d="$(m09_etat "$ex")"
  printf '%s %s [M09-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}

# m09_lire EXX CLÉ / m09_ecrire EXX CLÉ VALEUR / m09_effacer EXX CLÉ — petites valeurs d'état.
m09_lire() {
  local f
  f="$(m09_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m09_ecrire() {
  local d
  d="$(m09_etat "$1")"
  printf '%s\n' "$3" >"$d/$2"
}
m09_effacer() {
  local d
  d="$(m09_etat "$1")"
  rm -f -- "$d/$2"
}

# ---------------------------------------------------------------------------
# Accès aux nœuds
# ---------------------------------------------------------------------------

# m09_cible NŒUD — destination SSH : l'alias du nœud (HostName = IP MGMT : ne dépend pas du DNS).
m09_cible() {
  printf '%s\n' "$1"
}

# m09_ssh NŒUD "commande" — commande distante (sortie conservée), code de retour de la commande.
m09_ssh() {
  local n="$1"
  shift
  remote "$(m09_cible "$n")" "$@"
}

# m09_joignable NŒUD — une nouvelle connexion SSH aboutit.
m09_joignable() {
  ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8 "$(m09_cible "$1")" true >/dev/null 2>&1
}

# m09_quorate NŒUD — le nœud se voit dans une partition qui a le quorum.
m09_quorate() {
  m09_ssh "$1" "corosync-quorumtool -s 2>/dev/null" 2>/dev/null | grep -Eq '^Quorate:[[:space:]]+Yes'
}

# m09_attendre SECONDES COMMANDE [args…] — répète la commande (toutes les 5 s) jusqu'au succès.
m09_attendre() {
  local t="$1" i
  shift
  for ((i = 0; i < t; i += 5)); do
    if "$@"; then return 0; fi
    sleep 5
  done
  "$@"
}

# m09_pas_quorate NŒUD — négation (pour m09_attendre).
m09_pas_quorate() { ! m09_quorate "$1"; }

# m09_un_quorate — affiche le premier nœud joignable qui a le quorum (code 1 si aucun).
m09_un_quorate() {
  local n
  for n in "${_M09_NOEUDS[@]}"; do
    if m09_quorate "$n"; then
      printf '%s\n' "$n"
      return 0
    fi
  done
  return 1
}

# m09_cluster_sain — 3 nœuds joignables, tous dans la partition quorate à 3 votes.
m09_cluster_sain() {
  local n out
  for n in "${_M09_NOEUDS[@]}"; do
    if ! m09_joignable "$n"; then
      wb_avert "$n (${_M09_IP[$n]}) injoignable en SSH root depuis adm01"
      return 1
    fi
    out="$(m09_ssh "$n" "corosync-quorumtool -s 2>/dev/null" 2>/dev/null)" || true
    if ! grep -Eq '^Quorate:[[:space:]]+Yes' <<<"$out" || ! grep -Eq '^Total votes:[[:space:]]+3$' <<<"$out"; then
      wb_avert "$n : cluster hv-par1 pas sain avant la panne (quorum, 3 votes attendus) : lab/bin/check 09 35"
      return 1
    fi
  done
}

# m09_noeud_vip — nœud qui porte la VIP de l'API (10.10.10.200, M09-E18) ; rien si aucun.
m09_noeud_vip() {
  local n
  for n in "${_M09_NOEUDS[@]}"; do
    if m09_ssh "$n" "ip -4 -o addr show | grep -qF ' $_M09_VIP/'" >/dev/null 2>&1; then
      printf '%s\n' "$n"
      return 0
    fi
  done
}

# m09_json NŒUD "chemin pvesh" [options…] — GET pvesh en JSON (lecture seule).
m09_json() {
  local n="$1" p="$2"
  shift 2
  m09_ssh "$n" "pvesh get $p --output-format json $*" 2>/dev/null
}

# m09_vm_noeud VMID — nœud qui porte la VM (vide si absente).
m09_vm_noeud() {
  local n
  n="$(m09_un_quorate || echo hv01)"
  m09_json "$n" /cluster/resources --type vm | jq -r --argjson v "$1" '.[] | select(.vmid == $v) | .node' 2>/dev/null | head -n 1
}

# m09_stockage_actif NŒUD STOCKAGE — le stockage existe et est actif sur le nœud.
m09_stockage_actif() {
  m09_ssh "$1" "pvesm status --storage $2 2>/dev/null" 2>/dev/null | awk -v s="$2" '$1 == s && $3 == "active" { f = 1 } END { exit !f }'
}

# m09_ha_status — sortie de « ha-manager status » (depuis un nœud quorate, sinon hv01).
m09_ha_status() {
  local n
  n="$(m09_un_quorate || echo hv01)"
  m09_ssh "$n" "ha-manager status 2>/dev/null" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Script distant : prélude de pannes-lib.sh + aide propre au module
# ---------------------------------------------------------------------------
read -r -d '' _M09_AIDE_DISTANTE <<'AIDE' || true
TABLE=infoger_durcissement
# empreinte CHEMIN — « lien:<cible> », « sha256:<somme> » ou « absent »
empreinte() {
  if [ -L "$1" ]; then
    printf 'lien:%s\n' "$(readlink "$1")"
  elif [ -f "$1" ]; then
    printf 'sha256:%s\n' "$(sha256sum <"$1" | cut -d' ' -f1)"
  else
    printf 'absent\n'
  fi
}
_cle() { printf '%s' "$1" | tr '/' '_'; }
# garder FICHIER — copie unique du contenu (ou d'un lien, ou de l'absence) avant modification.
garder() {
  local b
  b="$WB_DIR/$WB_EX.$(_cle "$1")"
  [ -e "$b.orig" ] || [ -e "$b.lien" ] || [ -e "$b.absent" ] || {
    if [ -L "$1" ]; then readlink "$1" >"$b.lien"
    elif [ -f "$1" ]; then cat "$1" >"$b.orig"
    else : >"$b.absent"
    fi
  }
  chmod 600 "$b".* 2>/dev/null || true
}
# pose FICHIER — mémorise l'empreinte de l'état posé par la panne.
pose() { empreinte "$1" >"$WB_DIR/$WB_EX.$(_cle "$1").pose"; }
# encore_pose FICHIER — 0 si le fichier est toujours dans l'état posé par la panne.
encore_pose() {
  local p
  p="$WB_DIR/$WB_EX.$(_cle "$1").pose"
  [ -f "$p" ] && [ "$(empreinte "$1")" = "$(cat "$p")" ]
}
# rendre FICHIER — remet l'état d'origine si le fichier est encore celui posé par la panne.
#   Affiche « retabli » ou « repare ». Écrit par « cat > » : fonctionne dans /etc/pve (pmxcfs).
rendre() {
  local b r=repare
  b="$WB_DIR/$WB_EX.$(_cle "$1")"
  if [ -f "$b.pose" ] && encore_pose "$1"; then
    if [ -f "$b.lien" ]; then rm -f "$1" && ln -s "$(cat "$b.lien")" "$1"
    elif [ -f "$b.orig" ]; then cat "$b.orig" >"$1"
    elif [ -f "$b.absent" ]; then rm -f "$1"
    fi
    r=retabli
    journal "annulation : $1 rétabli"
  elif [ -f "$b.pose" ]; then
    journal "annulation : $1 modifié depuis l'injection (réparation), laissé tel quel"
  fi
  rm -f "$b.orig" "$b.lien" "$b.absent" "$b.pose"
  printf '%s\n' "$r"
}
# table_poser < règles — crée la table nftables dédiée (refus si elle existe déjà).
table_poser() {
  if nft list table inet "$TABLE" >/dev/null 2>&1; then return 1; fi
  { printf 'table inet %s {\n' "$TABLE"; cat; printf '}\n'; } | nft -f - || return 1
  : >"$WB_DIR/$WB_EX.table"
  journal "table nftables inet $TABLE posée"
}
# table_retirer — retire la table si c'est cette panne qui l'a posée et qu'elle est encore là.
table_retirer() {
  [ -f "$WB_DIR/$WB_EX.table" ] || return 0
  if nft list table inet "$TABLE" >/dev/null 2>&1; then
    nft delete table inet "$TABLE" && journal "annulation : table nftables inet $TABLE retirée"
  else
    journal "annulation : table nftables inet $TABLE déjà retirée (réparation)"
  fi
  rm -f "$WB_DIR/$WB_EX.table"
}
# version_corosync+ FICHIER — incrémente config_version (copie de travail, jamais /etc/pve direct).
version_corosync_plus() {
  perl -0pi -e 's/^(\s*config_version:\s*)(\d+)/$1.($2+1)/me' "$1"
}
# pve_ecrire_corosync FICHIER_NEUF — remplace /etc/pve/corosync.conf par la méthode de la doc
#   (copie .new dans /etc/pve puis renommage atomique).
pve_ecrire_corosync() {
  cat "$1" >/etc/pve/corosync.conf.new && mv /etc/pve/corosync.conf.new /etc/pve/corosync.conf
}
# stockage_section STOCKAGE CLÉ — valeur d'une propriété dans /etc/pve/storage.cfg (vide si absente).
stockage_section() {
  awk -v s="$1" -v k="$2" '
    /^[a-z]+: / { dans = ($2 == s) ; next }
    dans && $1 == k { $1 = ""; sub(/^ /, ""); print; exit }' /etc/pve/storage.cfg
}
AIDE

# m09_exec NŒUD [VAR=valeur…] <<'EOF' … EOF — script root sur le nœud imbriqué (SSH root@IP),
# précédé du prélude de pannes-lib.sh (journal, WB_DIR) et de l'aide ci-dessus.
m09_exec() {
  local n="$1"
  shift
  { printf '%s\n' "$_WB_PRELUDE"; _wb_entete "$@"; printf '%s\n' "$_M09_AIDE_DISTANTE"; cat; } \
    | remote "$(m09_cible "$n")" "bash -s"
}

# ---------------------------------------------------------------------------
# Pile HA : désarmement et réarmement (PVE 9.2)
# ---------------------------------------------------------------------------

# m09_ha_a_des_ressources — au moins une ressource HA est configurée.
m09_ha_a_des_ressources() {
  m09_ha_status | grep -Eq '^service '
}

# m09_ha_desarmee — la pile HA est désarmée (libellé « disarm » dans ha-manager status ; à confirmer
# sur ton lab, voir le corrigé).
m09_ha_desarmee() {
  m09_ha_status | grep -qi 'disarm'
}

# m09_ha_desarmee_complet — désarmement terminé : état « disarmed » (tous les watchdogs relâchés) ;
#   l'état intermédiaire « disarming » garde le watchdog du CRM actif (documentation HA, 9.2).
m09_ha_desarmee_complet() {
  m09_ha_status | grep -qiw 'disarmed'
}

# m09_ha_geler EXX — désarme la HA (mode freeze) si des ressources existent et qu'elle est armée.
#   Mémorise que c'est la panne qui l'a fait (clé ha-desarmee). Code ≠ 0 si impossible.
m09_ha_geler() {
  local ex="$1" n
  if ! m09_ha_a_des_ressources; then return 0; fi
  if m09_ha_desarmee_complet; then return 0; fi
  n="$(m09_un_quorate)" || { wb_avert "aucun nœud quorate : impossible de geler la HA"; return 1; }
  m09_ssh "$n" "ha-manager crm-command disarm-ha freeze" >/dev/null 2>&1 \
    || { wb_avert "ha-manager crm-command disarm-ha freeze refusé (Proxmox VE 9.2 requis)"; return 1; }
  m09_ecrire "$ex" ha-desarmee "$n"
  m09_journal "$ex" "pile HA désarmée (freeze) depuis $n"
  # Les LRM libèrent leur watchdog après avoir fini leurs tâches, puis le CRM le sien : on attend
  # l'état « disarmed » (pas seulement « disarming »).
  m09_attendre 120 m09_ha_desarmee_complet || { wb_avert "désarmement de la HA non constaté (état disarmed attendu)"; return 1; }
  sleep 20
}

# m09_ha_rearmer EXX — réarme la HA si c'est la panne qui l'a désarmée et qu'elle l'est encore.
m09_ha_rearmer() {
  local ex="$1" n
  [[ -n "$(m09_lire "$ex" ha-desarmee)" ]] || return 0
  if m09_ha_desarmee; then
    n="$(m09_un_quorate)" || { wb_avert "aucun nœud quorate : réarme la HA toi-même (ha-manager crm-command arm-ha)"; return 0; }
    if m09_ssh "$n" "ha-manager crm-command arm-ha" >/dev/null 2>&1; then
      m09_journal "$ex" "annulation : pile HA réarmée depuis $n"
    else
      wb_avert "réarmement de la HA refusé : lance « ha-manager crm-command arm-ha » sur un nœud quorate"
    fi
  else
    m09_journal "$ex" "annulation : pile HA déjà réarmée"
  fi
  m09_effacer "$ex" ha-desarmee
}

# ---------------------------------------------------------------------------
# Invités imbriqués de test (VMID 191-197)
# ---------------------------------------------------------------------------

# m09_vmid_libre VMID — aucun invité de ce numéro dans le cluster.
m09_vmid_libre() {
  [[ -z "$(m09_vm_noeud "$1")" ]]
}

# m09_vm_creer EXX VMID NOM NŒUD DISQUE — crée (sans la démarrer) une petite VM sans système :
#   256 Mio, 1 vCPU, pas de carte réseau, disque DISQUE (ex. « ceph-vm:1 »), étiquette pannes-m09.
m09_vm_creer() {
  local ex="$1" id="$2" nom="$3" n="$4" disque="$5"
  m09_ssh "$n" "qm create $id --name $nom --memory 256 --cores 1 --ostype l26 --scsihw virtio-scsi-single --scsi0 $disque --boot order=scsi0 --tags pannes-m09 --description 'Invité de test du palier 4 (M09)'" >/dev/null 2>&1 || return 1
  m09_ecrire "$ex" "vm-$id" "$n"
  m09_journal "$ex" "VM $id ($nom) créée sur $n, disque $disque"
}

# m09_vm_detruire EXX VMID — retire la VM de la HA et la détruit (où qu'elle soit), si c'est la panne
#   qui l'a créée. Supprime aussi un disque local orphelin laissé sur le nœud d'origine.
m09_vm_detruire() {
  local ex="$1" id="$2" orig n
  orig="$(m09_lire "$ex" "vm-$id")"
  [[ -n "$orig" ]] || return 0
  n="$(m09_un_quorate || echo hv01)"
  m09_ssh "$n" "ha-manager remove vm:$id" >/dev/null 2>&1 || true
  sleep 3
  n="$(m09_vm_noeud "$id")"
  if [[ -n "$n" ]]; then
    if ! m09_ssh "$n" "qm unlock $id 2>/dev/null; qm stop $id --skiplock 1 --timeout 30 >/dev/null 2>&1; qm destroy $id --purge 1 --destroy-unreferenced-disks 1 --skiplock 1" >/dev/null 2>&1; then
      # Disque introuvable (VM déplacée à la main…) : on retire la configuration, seulement si c'est
      # bien un invité de test des pannes (étiquette pannes-m09).
      m09_ssh "$n" "f=/etc/pve/nodes/$n/qemu-server/$id.conf; grep -q '^tags:.*pannes-m09' \$f && rm -f \$f" >/dev/null 2>&1 \
        || wb_avert "VM $id non détruite sur $n : qm destroy $id --purge 1 sur ce nœud"
    fi
  fi
  # Disques locaux restés sur un nœud (VM déplacée, réplication) : seulement les volumes de cette VM.
  local h
  for h in "${_M09_NOEUDS[@]}"; do
    m09_ssh "$h" "for v in \$(pvesm list local-lvm --vmid $id 2>/dev/null | awk 'NR > 1 { print \$1 }'); do pvesm free \$v; done; for v in \$(pvesm list zfs-local --vmid $id 2>/dev/null | awk 'NR > 1 { print \$1 }'); do pvesm free \$v; done" >/dev/null 2>&1 || true
  done
  m09_effacer "$ex" "vm-$id"
  m09_journal "$ex" "annulation : VM $id détruite"
}

# m09_ha_etat VMID — état HA de la ressource vm:VMID (started, error, …), vide si absente.
m09_ha_etat() {
  m09_ha_status | sed -nE "s/^service vm:$1 \\([^,]*, ([a-z_-]+)\\).*/\\1/p" | head -n 1
}

# ---------------------------------------------------------------------------
# Variantes sans effet sur un lab donné
# ---------------------------------------------------------------------------

# m09_essayer EXX NB DÉPART — appelle _mEXX_une N (codes : 0 panne posée et constatée, 10 variante
# sans effet sur ce lab, déjà défaite ; autre = erreur) pour N = DÉPART, DÉPART+1… jusqu'à un succès.
# La variante retenue est mise dans WB_VAR (enregistrée par wb_main ou par l'astreinte).
m09_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M09-$ex n'a d'effet sur ce lab (configuration inattendue)"
  return 1
}
