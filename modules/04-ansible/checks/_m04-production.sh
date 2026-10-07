# shellcheck shell=bash
# _m04-production.sh — fonctions partagées par les checks M04-E24 à M04-E34 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Variables de lab/lab.env utilisées : WB_PVE_HOST, WB_SRC, WB_DEPOT, WB_GITLAB_URL,
# WB_GITLAB_TOKEN_FILE, et (M04-E28) WB_SEMAPHORE_URL, WB_SEMAPHORE_TOKEN_FILE.

_M04_PROJET="projects/plateforme%2Fansible"
_M04_SRC="${WB_SRC:-$HOME/src}/ansible"
_M04_DOC="${WB_DEPOT:-$HOME/medisphere}/docs/socle"
_M04_SEM_URL="${WB_SEMAPHORE_URL:-https://sem01.par1.medisphere.internal}"
_M04_SEM_JETON="${WB_SEMAPHORE_TOKEN_FILE:-$HOME/.config/workbook/semaphore-checks.token}"

# --- Proxmox (root sur pve01 : ne dépend d'aucun jeton de l'apprenant) ------------------------

_M04_VMS_CACHE=""
# _m04_vms — JSON de /cluster/resources (VMs et templates), mis en cache pour le check.
#   Échoue si pve01 ne répond pas : un contrôle « aucune VM » ne doit jamais passer faute de données.
_m04_vms() {
  if [[ -z "$_M04_VMS_CACHE" ]]; then
    _M04_VMS_CACHE="$(remote "$WB_PVE_HOST" "pvesh get /cluster/resources --type vm --output-format json" 2>/dev/null)" \
      || _M04_VMS_CACHE="indisponible"
    jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$_M04_VMS_CACHE" || _M04_VMS_CACHE="indisponible"
  fi
  [[ "$_M04_VMS_CACHE" != "indisponible" ]] || return 1
  printf '%s\n' "$_M04_VMS_CACHE"
}
# _m04_charger — remplit le cache dans le shell courant (à appeler en tête de chaque check).
_m04_charger() { _m04_vms >/dev/null || true; }

# _m04_existe VMID — la VM ou le template existe.
_m04_existe() {
  local v
  v="$(_m04_vms)" || return 1
  jq -e --argjson v "$1" 'any(.[]; .vmid == $v)' >/dev/null <<<"$v"
}

# _m04_aucune_vm DEBUT FIN — aucune VM dans la plage de VMID (échoue si pve01 ne répond pas).
_m04_aucune_vm() {
  local v
  v="$(_m04_vms)" || return 1
  jq -e --argjson a "$1" --argjson b "$2" 'all(.[]; .vmid < $a or .vmid > $b)' >/dev/null <<<"$v"
}

# _m04_vm_filtre VMID 'filtre jq' — la VM existe et satisfait le filtre (champs de /cluster/resources).
_m04_vm_filtre() {
  local v
  v="$(_m04_vms)" || return 1
  jq -e --argjson v "$1" "any(.[]; .vmid == \$v and ($2))" >/dev/null <<<"$v"
}

# _m04_vm_conf VMID 'regex' — la configuration Proxmox de la VM (qm config) correspond à la regex.
_m04_vm_conf() { remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null | grep -Eq -- "$2"; }

# _m04_tache_pve TYPE VMID — une tâche Proxmox TYPE (qmclone, qmdestroy…) réussie existe pour VMID.
_m04_tache_pve() {
  remote "$WB_PVE_HOST" "pvesh get /nodes/\$(hostname)/tasks --typefilter $1 --vmid $2 --limit 20 --output-format json" 2>/dev/null \
    | jq -e 'any(.[]; .status == "OK")' >/dev/null
}

# _m04_privileges_role ROLE — privilèges du rôle Proxmox, un par ligne.
_m04_privileges_role() {
  remote "$WB_PVE_HOST" "pveum role list --output-format json" 2>/dev/null \
    | jq -r --arg r "$1" '.[] | select(.roleid == $r) | .privs | if type == "string" then split(",")[] else .[] end' \
    | tr -d ' '
}

# --- GitLab (jeton des checks) -----------------------------------------------------------------

# _m04_api_ok "chemin" 'filtre jq' — la réponse de l'API GitLab satisfait le filtre.
_m04_api_ok() {
  local r
  r="$(gitlab_api "$1" 2>/dev/null)" || return 1
  jq -e "$2" >/dev/null 2>&1 <<<"$r"
}

# _m04_fichier_main CHEMIN — le fichier existe sur la branche main de plateforme/ansible.
_m04_fichier_main() {
  local p
  p="$(jq -rn --arg p "$1" '$p | @uri')"
  gitlab_api "$_M04_PROJET/repository/files/$p?ref=main" >/dev/null 2>&1
}

# _m04_fichier_main_contient CHEMIN 'regex' — le contenu du fichier sur main correspond (grep -E).
_m04_fichier_main_contient() {
  local p
  p="$(jq -rn --arg p "$1" '$p | @uri')"
  gitlab_api "$_M04_PROJET/repository/files/$p/raw?ref=main" 2>/dev/null | grep -Eq -- "$2"
}

# _m04_fichier_main_sans CHEMIN 'regex' — le fichier existe sur main et ne contient PAS la regex.
_m04_fichier_main_sans() {
  local p contenu
  p="$(jq -rn --arg p "$1" '$p | @uri')"
  contenu="$(gitlab_api "$_M04_PROJET/repository/files/$p/raw?ref=main" 2>/dev/null)" || return 1
  ! grep -Eq -- "$2" <<<"$contenu"
}

# _m04_variable_ok CLE 'filtre jq' — une variable CI du projet nommée CLE satisfait le filtre
#   (toutes portées d'environnement confondues ; champs : protected, masked, variable_type,
#   environment_scope…).
_m04_variable_ok() {
  local r
  r="$(gitlab_api "$_M04_PROJET/variables?per_page=100" 2>/dev/null)" || return 1
  jq -e --arg k "$1" "any(.[]; .key == \$k and ($2))" >/dev/null 2>&1 <<<"$r"
}

# _m04_job_reussi 'regex du nom' — un job réussi récent du projet porte ce nom.
_m04_job_reussi() {
  gitlab_api "$_M04_PROJET/jobs?scope%5B%5D=success&per_page=100" 2>/dev/null \
    | jq -e --arg n "$1" 'any(.[]; .name | test($n))' >/dev/null
}

# _m04_job_dans_pipelines 'requête pipelines' 'regex du nom' 'statuts jq' — dans les pipelines
#   renvoyés par la requête, un job du nom donné a un statut de la liste (ex. '["success"]').
_m04_job_dans_pipelines() {
  local ids pid
  ids="$(gitlab_api "$_M04_PROJET/pipelines?$1" 2>/dev/null | jq -r '.[].id')" || return 1
  for pid in $ids; do
    gitlab_api "$_M04_PROJET/pipelines/$pid/jobs?per_page=100" 2>/dev/null \
      | jq -e --arg n "$2" --argjson s "$3" 'any(.[]; (.name | test($n)) and (.status as $x | $s | index($x)))' \
        >/dev/null && return 0
  done
  return 1
}

# --- Semaphore (jeton du compte workbook-checks, M04-E28) ---------------------------------------

# _m04_sem_api "chemin" — GET sur l'API de Semaphore (TLS vérifié), jeton en en-tête.
_m04_sem_api() {
  [[ -r "$_M04_SEM_JETON" ]] || { echo "jeton Semaphore des checks illisible : $_M04_SEM_JETON" >&2; return 1; }
  curl -sf --max-time "$WB_TIMEOUT" -H "Authorization: Bearer $(<"$_M04_SEM_JETON")" "$_M04_SEM_URL/api/$1"
}

# _m04_sem_ok "chemin" 'filtre jq' — la réponse de Semaphore satisfait le filtre.
_m04_sem_ok() {
  local r
  r="$(_m04_sem_api "$1" 2>/dev/null)" || return 1
  jq -e "$2" >/dev/null 2>&1 <<<"$r"
}

# _m04_sem_projet — identifiant du projet Semaphore dont le nom contient « socle » (vide sinon).
_m04_sem_projet() {
  _m04_sem_api projects 2>/dev/null | jq -r '[.[] | select(.name | test("socle"; "i"))][0].id // empty'
}

# --- Documentation et poste ---------------------------------------------------------------------

# _m04_doc_contient FICHIER 'regex'... — le document contient chaque motif (grep -Ei).
_m04_doc_contient() {
  local f="$1" m
  shift
  [[ -s "$f" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" "$f" || return 1; done
}

# _m04_pas_de_panne — aucune panne M04 marquée active sur adm01.
_m04_pas_de_panne() {
  ! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M04-* >/dev/null 2>&1
}
