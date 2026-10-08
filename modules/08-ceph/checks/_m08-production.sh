# shellcheck shell=bash
# _m08-production.sh — fonctions partagées par les checks M08-E24 à M08-E34 et M08-E46 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Variables de lab/lab.env utilisées : WB_CEPH_ADMIN (hôte « _admin », défaut ceph01), WB_PVE_HOST,
# WB_PBS_HOST, WB_DEPOT, WB_MOI, WB_GITLAB_URL, WB_GITLAB_TOKEN_FILE, WB_NETBOX_URL,
# WB_NETBOX_TOKEN_FILE.
# Toutes les commandes Ceph lancées ici sont des LECTURES (status, get, ls, dump, show, info).
# Les sorties qui contiennent des clés (auth ls) sont filtrées aussitôt : seules les capacités
# restent en mémoire, rien n'est affiché.

_M08P_ADMIN="${WB_CEPH_ADMIN:-ceph01}"
_M08P_NOEUDS=(ceph01 ceph02 ceph03)
_M08P_ZONE=par1.medisphere.internal
_M08P_RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt
_M08P_DEPOT="${WB_DEPOT:-$HOME/medisphere}"
_M08P_VERSION=20.2.4
# 1 Gio : osd_memory_target imposé par le PLAN (§4.9).
_M08P_MEM_OSD=1073741824

declare -A _M08P_IP_PUB=([ceph01]=10.10.30.51 [ceph02]=10.10.30.52 [ceph03]=10.10.30.53 [cephcli01]=10.10.30.20)
declare -A _M08P_IP_CLU=([ceph01]=10.10.31.51 [ceph02]=10.10.31.52 [ceph03]=10.10.31.53)

# --- Accès au cluster (hôte _admin, sudo) ------------------------------------------------------

# _m08p_outil OUTIL "ARGUMENTS" — lance ceph, rbd ou radosgw-admin sur l'hôte _admin : le binaire
# de l'hôte s'il existe (ceph-common), sinon dans « cephadm shell ». Sortie standard seule.
_m08p_outil() {
  local o="$1" a="$2"
  remote "$_M08P_ADMIN" "if command -v $o >/dev/null 2>&1; then sudo -n $o $a; else sudo -n cephadm shell -- $o $a; fi" 2>/dev/null
}
_m08p_ceph() { _m08p_outil ceph "$1"; }
_m08p_rbd() { _m08p_outil rbd "$1"; }
_m08p_rgw() { _m08p_outil radosgw-admin "$1"; }

# _m08p_json "ARGUMENTS ceph" — sortie JSON valide de ceph, ou « null ».
_m08p_json() {
  local s
  s="$(_m08p_ceph "$1 --format json")" || s=""
  if jq -e . >/dev/null 2>&1 <<<"$s"; then printf '%s\n' "$s"; else echo null; fi
}

# Caches remplis par _m08p_charger dans le shell courant (à appeler en tête de chaque check).
_M08P_STATUS=null
_M08P_SANTE=null
_M08P_CONFIG=null
_M08P_POOLS=null
_M08P_PS=null
_M08P_AUTH=null
_M08P_HOTES=null
_m08p_charger() {
  _M08P_STATUS="$(_m08p_json status)"
  _M08P_SANTE="$(_m08p_json 'health detail')"
  _M08P_CONFIG="$(_m08p_json 'config dump')"
  _M08P_POOLS="$(_m08p_json 'osd pool ls detail')"
  _M08P_PS="$(_m08p_json 'orch ps')"
  _M08P_HOTES="$(_m08p_json 'orch host ls')"
  # Les clés sont retirées immédiatement : seules les entités et leurs capacités sont gardées.
  _M08P_AUTH="$(_m08p_json 'auth ls' | jq -c '[.auth_dump[]? | {entity, caps}]' 2>/dev/null)" || _M08P_AUTH=null
  [[ -n "$_M08P_AUTH" ]] || _M08P_AUTH=null
}

# _m08p_jq "NOM_CACHE" FILTRE — filtre booléen jq sur un cache (_M08P_STATUS…).
_m08p_jq() {
  local -n _c="$1"
  [[ "$_c" != null ]] && jq -e "$2" >/dev/null 2>&1 <<<"$_c"
}

# _m08p_joignable — le cluster répond (sinon tous les contrôles suivants sont rouges, à raison).
_m08p_joignable() { _m08p_jq _M08P_STATUS '.fsid | length > 0'; }

# --- Santé -------------------------------------------------------------------------------------

_m08p_sante_ok() { _m08p_jq _M08P_SANTE '.status == "HEALTH_OK"'; }

# _m08p_controle_absent CODE — le contrôle n'est pas présent (ni actif, ni en sourdine).
_m08p_controle_absent() { _m08p_jq _M08P_SANTE "(.checks // {}) | has(\"$1\") | not"; }

# _m08p_seuls_controles REGEX — tout contrôle présent et non en sourdine a un code qui correspond.
_m08p_seuls_controles() {
  _m08p_jq _M08P_SANTE "[(.checks // {}) | to_entries[] | select((.value.muted // false) | not) | .key]
    | all(test(\"$1\"))"
}

# _m08p_sourdines_temporaires [REGEX] — toute mise en sourdine a une durée (ni « sticky », ni sans
# expiration) et, si REGEX est fourni, porte sur un code admis. Format JSON de « mutes » à confirmer
# sur ton lab (champs sticky et ttl).
_m08p_sourdines_temporaires() {
  local r="${1:-.}"
  _m08p_jq _M08P_SANTE "[(.mutes // [])[] | ((.sticky // false) | not) and (has(\"ttl\")) and (.code | test(\"$r\"))] | all"
}

# --- Configuration centrale ----------------------------------------------------------------------

# _m08p_config_get QUI OPTION — valeur résolue par « ceph config get ».
_m08p_config_get() { _m08p_ceph "config get $1 $2" | tr -d '[:space:]'; }

# _m08p_config_show DÉMON OPTION — valeur EN VIGUEUR dans un démon (« ceph config show »).
_m08p_config_show() { _m08p_ceph "config show $1 $2" | tr -d '[:space:]'; }

# _m08p_config_entree SECTION OPTION — l'option est posée à ce niveau exact (sans masque).
_m08p_config_entree() {
  _m08p_jq _M08P_CONFIG "any(.[]; .section == \"$1\" and .name == \"$2\" and ((.mask // \"\") == \"\"))"
}

# _m08p_config_valeur SECTION OPTION VALEUR — l'option vaut VALEUR à ce niveau exact.
_m08p_config_valeur() {
  _m08p_jq _M08P_CONFIG "any(.[]; .section == \"$1\" and .name == \"$2\" and ((.mask // \"\") == \"\") and (.value | tostring) == \"$3\")"
}

# --- Démons, OSD, pools --------------------------------------------------------------------------

# _m08p_demons TYPE — noms (type.id) des démons d'un type, d'après l'orchestrateur.
_m08p_demons() {
  [[ "$_M08P_PS" != null ]] || return 1
  jq -r --arg t "$1" '.[] | select(.daemon_type == $t) | "\(.daemon_type).\(.daemon_id)"' <<<"$_M08P_PS"
}

# _m08p_hotes_type TYPE — hôtes qui portent au moins un démon de ce type.
_m08p_hotes_type() {
  [[ "$_M08P_PS" != null ]] || return 1
  jq -r --arg t "$1" '[.[] | select(.daemon_type == $t) | .hostname] | unique[]' <<<"$_M08P_PS"
}

# _m08p_hotes_orch — hôtes connus de l'orchestrateur (ceph01-03, et ceph04 jusqu'au mini-projet).
_m08p_hotes_orch() {
  [[ "$_M08P_HOTES" != null ]] || return 1
  jq -r '.[].hostname' <<<"$_M08P_HOTES"
}

_m08p_osd_ids() { _m08p_ceph "osd ls" | grep -E '^[0-9]+$'; }

# _m08p_pool_existe NOM / _m08p_pool_absent NOM
_m08p_pool_existe() { _m08p_jq _M08P_POOLS "any(.[]; .pool_name == \"$1\")"; }
_m08p_pool_absent() { _m08p_jq _M08P_POOLS "any(.[]; .pool_name == \"$1\") | not"; }

# _m08p_pool_app NOM APP — l'application est activée sur le pool.
_m08p_pool_app() { _m08p_jq _M08P_POOLS "any(.[]; .pool_name == \"$1\" and ((.application_metadata // {}) | has(\"$2\")))"; }

# _m08p_pool_quota_min NOM OCTETS — quota en octets posé et au moins égal à OCTETS (1 = « posé »).
_m08p_pool_quota_min() {
  local q
  q="$(_m08p_json "osd pool get-quota $1" | jq -r '.quota_max_bytes // 0' 2>/dev/null)" || return 1
  [[ "$q" =~ ^[0-9]+$ ]] && ((q > 0 && q >= $2))
}

# _m08p_pool_classe NOM CLASSE — la règle CRUSH du pool prend ses OSD dans la classe CLASSE
# (étape « take » sur « <racine>~<classe> »), quel que soit le nom de la règle.
_m08p_pool_classe() {
  local regle
  [[ "$_M08P_POOLS" != null ]] || return 1
  regle="$(jq -r --arg p "$1" '.[] | select(.pool_name == $p) | .crush_rule' <<<"$_M08P_POOLS")" || return 1
  [[ "$regle" =~ ^[0-9]+$ ]] || return 1
  _m08p_json "osd crush rule dump" | jq -e --argjson r "$regle" --arg c "$2" \
    'any(.[]; .rule_id == $r and any(.steps[]; .op == "take" and (.item_name | endswith("~" + $c))))' >/dev/null
}

# --- Identités cephx (capacités seulement) -------------------------------------------------------

_m08p_entite_existe() { _m08p_jq _M08P_AUTH "any(.[]; .entity == \"$1\")"; }
_m08p_entite_absente() { _m08p_jq _M08P_AUTH "any(.[]; .entity == \"$1\") | not"; }

# _m08p_caps ENTITÉ SERVICE REGEX — la capacité du service (mon, osd, mds, mgr) correspond.
_m08p_caps() {
  _m08p_jq _M08P_AUTH "any(.[]; .entity == \"$1\" and ((.caps.$2 // \"\") | test(\"$3\")))"
}

# _m08p_sans_allow_tout ENTITÉ — aucune capacité « allow * » (ni « allow rwx » sur les OSD).
_m08p_sans_allow_tout() {
  _m08p_jq _M08P_AUTH "any(.[]; .entity == \"$1\")
    and all(.[] | select(.entity == \"$1\") | .caps | to_entries[]; (.value | test(\"allow \\\\*|allow rwx\") | not))"
}

# --- Réseau et hôtes --------------------------------------------------------------------------------

# _m08p_mtu HÔTE INTERFACE VALEUR — MTU de l'interface dans l'invité.
_m08p_mtu() { remote "$1" "ip -o link show $2" 2>/dev/null | grep -q "mtu $3 "; }

# _m08p_ping_jumbo HÔTE DESTINATION — 9000 octets sans fragmentation (8972 + 28 d'en-têtes).
_m08p_ping_jumbo() { remote "$1" "ping -c 2 -W 2 -M do -s 8972 $2" >/dev/null 2>&1; }

# _m08p_crypt HÔTE N — au moins N périphériques dm-crypt sur l'hôte (OSD chiffrés).
_m08p_crypt() {
  local n
  n="$(remote "$1" "lsblk -nr -o TYPE" 2>/dev/null | grep -c '^crypt$')" || n=0
  ((n >= $2))
}

# --- Certificats -------------------------------------------------------------------------------------

# _m08p_cert NOM PORT JOURS [ADRESSE] — chaîne vers la racine MédiSphère, nom vérifié, plus de JOURS
# jours restants et durée de vie de 31 jours au plus (ACME, politique M06-E33).
_m08p_cert() {
  local pem cible="${4:-$1}" debut fin
  pem="$(openssl s_client -connect "$cible:$2" -servername "$1" -CAfile "$_M08P_RACINE" -verify_hostname "$1" \
    -verify_return_error </dev/null 2>/dev/null | openssl x509 2>/dev/null)" || return 1
  [[ -n "$pem" ]] || return 1
  openssl x509 -noout -checkend $(($3 * 86400)) <<<"$pem" >/dev/null || return 1
  debut="$(date -d "$(openssl x509 -noout -startdate <<<"$pem" | cut -d= -f2)" +%s)" || return 1
  fin="$(date -d "$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)" +%s)" || return 1
  (((fin - debut) <= 31 * 86400))
}

# --- GitLab (jeton des checks, lecture) -----------------------------------------------------------

# _m08p_fichier_main PROJET CHEMIN — contenu d'un fichier de la branche main.
_m08p_fichier_main() {
  local p="${1//\//%2F}" f="${2//\//%2F}"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m08p_doc_main CHEMIN REGEX... — le fichier existe sur main de plateforme/medisphere et contient
# chaque motif (grep -E, insensible à la casse).
_m08p_doc_main() {
  local c m chemin="$1"
  shift
  c="$(_m08p_fichier_main plateforme/medisphere "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m08p_doc_prefixe DOSSIER PRÉFIXE — un fichier « PRÉFIXE* » existe sous DOSSIER (récursif) sur main
# de plateforme/medisphere.
_m08p_doc_prefixe() {
  local d="${1//\//%2F}"
  gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=$d&recursive=true&per_page=100" 2>/dev/null \
    | jq -e --arg p "$2" 'any(.[]?; .type == "blob" and (.name | startswith($p)))' >/dev/null
}

# _m08p_arbre_non_vide PROJET DOSSIER — le dossier contient au moins un fichier sur main.
_m08p_arbre_non_vide() {
  local p="${1//\//%2F}" d="${2//\//%2F}"
  gitlab_api "projects/$p/repository/tree?ref=main&path=$d&recursive=true&per_page=100" 2>/dev/null \
    | jq -e 'any(.[]?; .type == "blob")' >/dev/null
}

# _m08p_pipeline_ok PROJET — dernier pipeline de main réussi (« manual » : jobs manuels non lancés).
_m08p_pipeline_ok() {
  local p="${1//\//%2F}"
  gitlab_api "projects/$p/pipelines?ref=main&per_page=1" 2>/dev/null \
    | jq -e '.[0].status == "success" or .[0].status == "manual"' >/dev/null
}

# _m08p_job_reussi PROJET MOTIF — un job de main dont le nom contient MOTIF a réussi (100 derniers).
_m08p_job_reussi() {
  local p="${1//\//%2F}"
  gitlab_api "projects/$p/jobs?scope%5B%5D=success&per_page=100" 2>/dev/null \
    | jq -e --arg m "$2" 'any(.[]?; .ref == "main" and (.name | contains($m)))' >/dev/null
}

# _m08p_recherche_main PROJET TEXTE — le texte apparaît dans un fichier de main (recherche GitLab).
_m08p_recherche_main() {
  local p="${1//\//%2F}" t
  t="$(jq -rn --arg t "$2" '$t | @uri')"
  gitlab_api "projects/$p/search?scope=blobs&ref=main&search=$t" 2>/dev/null | jq -e 'length > 0' >/dev/null
}

# --- PBS et Proxmox ------------------------------------------------------------------------------------

# _m08p_pbs_recent MOTIF_ARCHIVE HEURES — dans l'espace de noms par1/ceph du datastore ds-lab, un
# instantané de moins de HEURES heures contient une archive dont le nom correspond au motif
# (ex. « *rbd*.didx »). Lecture du datastore en root sur pbs01.
_m08p_pbs_recent() {
  remote "$WB_PBS_HOST" "
    p=\$(proxmox-backup-manager datastore show ds-lab --output-format json | sed -nE 's/.*\"path\" *: *\"([^\"]+)\".*/\1/p')
    [ -n \"\$p\" ] || exit 1
    find \"\$p/ns/par1/ns/ceph\" -mindepth 4 -maxdepth 4 -type f -name '$1' -mmin -$(($2 * 60)) 2>/dev/null | grep -q ." \
    >/dev/null 2>&1
}

# _m08p_vm_absente VMID — la VM n'existe plus (échoue si pve01 ne répond pas).
_m08p_vm_absente() {
  remote "$WB_PVE_HOST" "true" >/dev/null 2>&1 || return 1
  ! remote "$WB_PVE_HOST" "qm status $1" >/dev/null 2>&1
}

# _m08p_vm_mtu VMID NETN — la carte réseau Proxmox a mtu=9000.
_m08p_vm_mtu() { remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null | grep -Eq "^$2: .*mtu=9000"; }

# --- Divers ----------------------------------------------------------------------------------------------

# _m08p_aucune_panne_active — aucune panne M08 marquée par lab/bin/break.
_m08p_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"
  [[ -z "$(find "$d" -maxdepth 1 -name 'M08-E*' 2>/dev/null)" ]]
}

# _m08p_identite_ok HÔTE ID CIBLE — depuis HÔTE, « rbd ls CIBLE » réussit avec l'identité ID.
# _m08p_identite_refus HÔTE ID CIBLE — même commande, refusée (échoue si l'hôte ne répond pas).
_m08p_identite_ok() { remote "$1" "sudo -n timeout 20 rbd ls $3 --id $2" >/dev/null 2>&1; }
_m08p_identite_refus() {
  remote "$1" true >/dev/null 2>&1 || return 1
  ! remote "$1" "sudo -n timeout 20 rbd ls $3 --id $2" >/dev/null 2>&1
}
