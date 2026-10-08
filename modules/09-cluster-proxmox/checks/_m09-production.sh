# shellcheck shell=bash
# _m09-production.sh — fonctions partagées par les checks M09-E24 à M09-E34 et M09-E46 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Accès : root sur les nœuds imbriqués par leurs alias SSH hv01, hv02, hv03 (~/.ssh/config de adm01,
# HostName = IP MGMT, User root ; clé de adm01 posée par le fichier de réponse, M09-E03) ; root sur pve01 et pbs01 comme dans les modules précédents ;
# API GitLab en lecture (jeton des checks). Le traitement JSON se fait sur adm01 (jq), jamais sur
# les nœuds (jq n'y est pas forcément installé).
# Variables de lab/lab.env utilisées : WB_PVE_HOST, WB_PBS_HOST, WB_SRC, WB_GITLAB_*.

_M09P_ZONE=par1.medisphere.internal
_M09P_NOEUDS=(hv01 hv02 hv03)
declare -A _M09P_VMID=([hv01]=2091 [hv02]=2092 [hv03]=2093)
_M09P_VIP=10.10.10.200
_M09P_RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt
_M09P_SRC="${WB_SRC:-$HOME/src}"

# --- Nœuds -----------------------------------------------------------------------------------

# _m09p_hv NŒUD COMMANDE — exécute une commande en root sur un nœud imbriqué.
_m09p_hv() {
  local n="$1"
  shift
  remote "$n" "$@"
}

_M09P_NOEUD=""
# _m09p_noeud — premier nœud qui répond (mis en cache). Échoue si aucun.
_m09p_noeud() {
  local n
  if [[ -z "$_M09P_NOEUD" ]]; then
    for n in "${_M09P_NOEUDS[@]}"; do
      if _m09p_hv "$n" true >/dev/null 2>&1; then
        _M09P_NOEUD="$n"
        break
      fi
    done
  fi
  [[ -n "$_M09P_NOEUD" ]] || return 1
  printf '%s\n' "$_M09P_NOEUD"
}

# _m09p_charger — fixe le nœud de référence dans le shell courant (à appeler en tête de check).
_m09p_charger() {
  _m09p_noeud >/dev/null || true
}

# _m09p_pvesh CHEMIN [ARGS…] — JSON de « pvesh get » sur le nœud de référence.
_m09p_pvesh() {
  local n
  n="$(_m09p_noeud)" || return 1
  _m09p_hv "$n" "pvesh get $* --output-format json" 2>/dev/null
}

# _m09p_pvesh_jq CHEMIN FILTRE_JQ — filtre booléen sur le JSON de pvesh (échoue si illisible).
_m09p_pvesh_jq() {
  local j
  j="$(_m09p_pvesh "$1")" || return 1
  [[ -n "$j" ]] && jq -e "$2" >/dev/null 2>&1 <<<"$j"
}

# _m09p_ceph_jq SOUS-COMMANDE FILTRE_JQ — filtre booléen sur « ceph <sous-commande> --format json ».
_m09p_ceph_jq() {
  local n j
  n="$(_m09p_noeud)" || return 1
  j="$(_m09p_hv "$n" "ceph $1 --format json" 2>/dev/null)" || return 1
  [[ -n "$j" ]] && jq -e "$2" >/dev/null 2>&1 <<<"$j"
}

# _m09p_tous COMMANDE — la commande réussit sur chacun des trois nœuds.
_m09p_tous() {
  local n
  for n in "${_M09P_NOEUDS[@]}"; do
    _m09p_hv "$n" "$1" >/dev/null 2>&1 || return 1
  done
}

# _m09p_quorate_3 — cluster quorate, trois nœuds en ligne.
_m09p_quorate_3() {
  _m09p_pvesh_jq /cluster/status \
    '(.[] | select(.type == "cluster") | .quorate) == 1
     and ([.[] | select(.type == "node" and .online == 1)] | length) == 3'
}

# _m09p_ha_sans_erreur — aucune ressource HA en error, fence ou recovery.
_m09p_ha_sans_erreur() {
  _m09p_pvesh_jq /cluster/ha/status/current \
    '[.[] | select(.type == "service" and ((.state // "") | test("^(error|fence|recovery)$")))] | length == 0'
}

# _m09p_ceph_ok — Ceph en HEALTH_OK.
_m09p_ceph_ok() {
  _m09p_ceph_jq health '.status == "HEALTH_OK"'
}

# _m09p_vip_unique — la VIP est portée par exactement un nœud.
_m09p_vip_unique() {
  local n c total=0
  for n in "${_M09P_NOEUDS[@]}"; do
    c="$(_m09p_hv "$n" "ip -o -4 addr show | grep -c ' $_M09P_VIP/' || true" 2>/dev/null)" || return 1
    total=$((total + ${c:-0}))
  done
  ((total == 1))
}

# _m09p_vm_cluster VMID FILTRE_JQ — filtre booléen sur la VM imbriquée (échoue si absente).
_m09p_vm_cluster() {
  _m09p_pvesh_jq "/cluster/resources --type vm" \
    "[.[] | select(.vmid == $1)] | length == 1 and (.[0] | $2)"
}

# _m09p_vm_cluster_absente VMID — la VM imbriquée n'existe plus (échoue si l'API ne répond pas).
_m09p_vm_cluster_absente() {
  _m09p_pvesh_jq "/cluster/resources --type vm" "[.[] | select(.vmid == $1)] | length == 0"
}

# _m09p_vm_noeud VMID — nœud qui porte la VM imbriquée.
_m09p_vm_noeud() {
  local j
  j="$(_m09p_pvesh "/cluster/resources --type vm")" || return 1
  jq -er --argjson id "$1" '[.[] | select(.vmid == $id) | .node] | first // empty' <<<"$j"
}

# _m09p_vm_config VMID — « qm config » de la VM imbriquée, lu sur son nœud.
_m09p_vm_config() {
  local n
  n="$(_m09p_vm_noeud "$1")" || return 1
  _m09p_hv "$n" "qm config $1"
}

# --- pve01 -------------------------------------------------------------------------------------

# _m09p_creations VMID — nombre de tâches de création (qmcreate, qmclone, qmrestore) pour ce VMID
# dans le journal de pve01 ; avec un second argument SECONDES, seulement les plus récentes.
_m09p_creations() {
  local j depuis=0
  [[ -n "${2:-}" ]] && depuis=$(($(date +%s) - $2))
  j="$(remote "$WB_PVE_HOST" "pvesh get /nodes/\$(hostname)/tasks --vmid $1 --source all --limit 1000 --output-format json" 2>/dev/null)" || return 1
  jq --argjson d "$depuis" '[.[] | select((.type | test("^(qmcreate|qmclone|qmrestore)$")) and (.starttime // 0) >= $d)] | length' <<<"$j"
}

# _m09p_creations_min VMID N [SECONDES] — au moins N créations.
_m09p_creations_min() {
  local c
  c="$(_m09p_creations "$1" "${3:-}")" || return 1
  [[ "$c" =~ ^[0-9]+$ ]] && ((c >= $2))
}

# --- Certificats ---------------------------------------------------------------------------------

# _m09p_cert_ok NOM PORT JOURS — chaîne vers la racine MédiSphère, nom vérifié, plus de JOURS jours
# restants, et durée totale de 31 jours au plus (certificat ACME de la politique M06-E27).
_m09p_cert_ok() {
  local pem debut fin
  pem="$(openssl s_client -connect "$1:$2" -servername "$1" -CAfile "$_M09P_RACINE" -verify_hostname "$1" \
    -verify_return_error </dev/null 2>/dev/null | openssl x509 2>/dev/null)" || return 1
  [[ -n "$pem" ]] || return 1
  openssl x509 -noout -checkend $(($3 * 86400)) <<<"$pem" >/dev/null || return 1
  debut="$(date -d "$(openssl x509 -noout -startdate <<<"$pem" | cut -d= -f2)" +%s)" || return 1
  fin="$(date -d "$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)" +%s)" || return 1
  ((fin - debut <= 31 * 86400 + 3600))
}

# --- Réseau ------------------------------------------------------------------------------------

# _m09p_port_ferme HÔTE_SSH DESTINATION PORT — depuis l'hôte, connexion TCP impossible. Échoue si
# l'hôte source ne répond pas (sinon : faux positif).
_m09p_port_ferme() {
  remote "$1" true >/dev/null 2>&1 || return 1
  remote "$1" "! timeout 4 bash -c 'exec 3<>/dev/tcp/$2/$3' 2>/dev/null"
}

# _m09p_port_ouvert HÔTE_SSH DESTINATION PORT — depuis l'hôte, connexion TCP possible.
_m09p_port_ouvert() {
  remote "$1" "timeout 4 bash -c 'exec 3<>/dev/tcp/$2/$3'" >/dev/null 2>&1
}

# --- GitLab (jeton des checks, lecture) --------------------------------------------------------

# _m09p_fichier_main PROJET CHEMIN — contenu d'un fichier de la branche main.
_m09p_fichier_main() {
  local p="${1//\//%2F}" f="${2//\//%2F}"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m09p_fichier_existe PROJET CHEMIN — le fichier existe sur main (et n'est pas vide).
_m09p_fichier_existe() {
  local c
  c="$(_m09p_fichier_main "$1" "$2" 2>/dev/null)" || return 1
  [[ -n "$c" ]]
}

# _m09p_doc DOSSIER PRÉFIXE — un fichier « PRÉFIXE* » existe dans docs/virtualisation/DOSSIER
# de plateforme/medisphere (DOSSIER vide : docs/virtualisation lui-même).
_m09p_doc() {
  local chemin="docs/virtualisation${1:+/$1}"
  gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=${chemin//\//%2F}&per_page=100" 2>/dev/null \
    | jq -e --arg p "$2" 'any(.[]?; .type == "blob" and (.name | startswith($p)))' >/dev/null
}

# _m09p_doc_contenu DOSSIER PRÉFIXE — contenu du premier fichier « PRÉFIXE* » du dossier.
_m09p_doc_contenu() {
  local chemin="docs/virtualisation${1:+/$1}" nom
  nom="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=${chemin//\//%2F}&per_page=100" 2>/dev/null \
    | jq -r --arg p "$2" '[.[]? | select(.type == "blob" and (.name | startswith($p))) | .name] | first // empty')" || return 1
  [[ -n "$nom" ]] || return 1
  _m09p_fichier_main plateforme/medisphere "$chemin/$nom"
}

# _m09p_job_reussi PROJET MOTIF — un job de main dont le nom contient MOTIF a réussi (100 derniers).
_m09p_job_reussi() {
  local p="${1//\//%2F}"
  gitlab_api "projects/$p/jobs?scope%5B%5D=success&per_page=100" 2>/dev/null \
    | jq -e --arg m "$2" 'any(.[]?; .ref == "main" and (.name | contains($m)))' >/dev/null
}
