# shellcheck shell=bash
# _m10-production.sh — fonctions partagées par les checks M10-E24 à M10-E34 et M10-E46 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Variables de lab/lab.env utilisées : WB_OS_CLOUD (nuage clouds.yaml de lecture globale, défaut
# medisphere-admin), WB_SRC, WB_DEPOT, WB_PVE_HOST, WB_PBS_HOST, WB_GITLAB_URL, WB_GITLAB_TOKEN_FILE.
# La CLI openstack (10.x) et ses greffons (octavia, placement) doivent être installés sur adm01.

_M10P_RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt
_M10P_CLOUD="${WB_OS_CLOUD:-medisphere-admin}"
_M10P_SRC="${WB_SRC:-$HOME/src}"
_M10P_DEPOT="${WB_DEPOT:-$HOME/medisphere}"
_M10P_NOEUDS=(osctl01 oscmp01 oscmp02)
_M10P_VIP_INT=10.10.50.200
_M10P_VIP_EXT=10.10.50.201
_M10P_NOM_INT=openstack-int.par1.medisphere.internal
_M10P_NOM_EXT=openstack.par1.medisphere.internal

# --- OpenStack --------------------------------------------------------------------------------

# _m10p_os ARGS… — CLI openstack, nuage des checks, JSON, délai borné. Échoue si l'appel échoue.
_m10p_os() {
  timeout 90 openstack --os-cloud "$_M10P_CLOUD" "$@" -f json 2>/dev/null
}

_M10P_CS="null"
_M10P_NA="null"
_M10P_VS="null"
# _m10p_charger — services de calcul, agents réseau, services de volume (en cache, shell courant).
_m10p_charger() {
  _M10P_CS="$(_m10p_os compute service list --long || echo null)"
  _M10P_NA="$(_m10p_os network agent list || echo null)"
  _M10P_VS="$(_m10p_os volume service list || echo null)"
}

# _m10p_calcul_up — liste lisible, non vide, tous les services Nova « up » et activés.
_m10p_calcul_up() {
  jq -e 'type == "array" and length > 0 and all(.[]; .State == "up" and .Status == "enabled")' >/dev/null <<<"$_M10P_CS"
}
# _m10p_agents_vivants — liste lisible, non vide, tous les agents vivants, passerelle présente.
_m10p_agents_vivants() {
  jq -e 'type == "array" and length > 0 and all(.[]; .Alive == true) and any(.[]; .["Agent Type"] | test("Gateway"))' \
    >/dev/null <<<"$_M10P_NA"
}
# _m10p_volumes_up — cinder-scheduler, cinder-volume et cinder-backup présents, activés, « up ».
_m10p_volumes_up() {
  jq -e 'type == "array" and all(.[]; .State == "up" and .Status == "enabled")
         and ([.[].Binary] | contains(["cinder-scheduler", "cinder-volume", "cinder-backup"]))' >/dev/null <<<"$_M10P_VS"
}

# _m10p_aucune_instance PRÉFIXE — aucune instance (tous projets) dont le nom commence par PRÉFIXE.
# Échoue si la liste est illisible (jamais de faux succès).
_m10p_aucune_instance() {
  local l
  l="$(_m10p_os server list --all-projects --name "^$1")" || return 1
  jq -e 'type == "array" and length == 0' >/dev/null <<<"$l"
}

# _m10p_projet_absent NOM DOMAINE — le projet n'existe pas (la liste du domaine est lisible).
_m10p_projet_absent() {
  local l
  l="$(_m10p_os project list --domain "$2")" || return 1
  jq -e --arg n "$1" 'type == "array" and (any(.[]; .Name == $n) | not)' >/dev/null <<<"$l"
}

# _m10p_quota PROJET CLÉ — valeur d'un quota (« quota show » : objet clé/valeur ou liste Resource/Limit).
_m10p_quota() {
  _m10p_os quota show "$1" | jq -r --arg k "$2" 'if type == "array" then (map({(.Resource): .Limit}) | add) else . end | .[$k] // empty'
}

# --- Nœuds ---------------------------------------------------------------------------------------

# _m10p_conteneurs_sains HÔTE — Docker répond, au moins un conteneur, aucun unhealthy/arrêté/mort.
_m10p_conteneurs_sains() {
  # shellcheck disable=SC2016  # évalué sur le nœud
  remote "$1" 'out=$(sudo -n docker ps -a --format "{{.Names}} {{.Status}}") || exit 1
               [ -n "$out" ] || exit 1
               ! printf "%s\n" "$out" | grep -Eq "unhealthy|Exited|Dead|Restarting"' >/dev/null 2>&1
}

# _m10p_port_ouvert HÔTE_SSH DESTINATION PORT — depuis l'hôte, connexion TCP possible.
_m10p_port_ouvert() {
  remote "$1" "timeout 4 bash -c 'exec 3<>/dev/tcp/$2/$3'" >/dev/null 2>&1
}

# _m10p_unite_ok HÔTE BASE — BASE.timer activé et actif, BASE.service déjà exécuté avec succès.
# HÔTE « local » : sur adm01 elle-même.
_m10p_unite_ok() {
  # shellcheck disable=SC2016  # évalué par bash -c ou sur l'hôte distant
  local cmd='systemctl is-enabled --quiet "$0.timer" && systemctl is-active --quiet "$0.timer" \
    && [ "$(systemctl show -p ExecMainStartTimestampMonotonic --value "$0.service")" != 0 ] \
    && [ "$(systemctl show -p Result --value "$0.service")" = success ]'
  if [[ "$1" == local ]]; then
    bash -c "$cmd" "$2"
  else
    remote "$1" "bash -c '$cmd' '$2'" >/dev/null 2>&1
  fi
}

# --- Certificats ----------------------------------------------------------------------------------

# _m10p_cert_vip NOM ADRESSE PORT — certificat servi : chaîne vers la racine MédiSphère, nom correct,
# expire dans plus de 10 jours, durée de vie de 31 jours au plus.
_m10p_cert_vip() {
  local pem debut fin
  pem="$(openssl s_client -connect "$2:$3" -servername "$1" -CAfile "$_M10P_RACINE" -verify_hostname "$1" \
    -verify_return_error </dev/null 2>/dev/null | openssl x509 2>/dev/null)" || return 1
  [[ -n "$pem" ]] || return 1
  openssl x509 -noout -checkend 864000 <<<"$pem" >/dev/null || return 1
  debut="$(date -d "$(openssl x509 -noout -startdate <<<"$pem" | cut -d= -f2)" +%s)" || return 1
  fin="$(date -d "$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)" +%s)" || return 1
  (((fin - debut) <= 31 * 86400))
}

# --- GitLab (jeton des checks, lecture) -----------------------------------------------------------

# _m10p_fichier_main PROJET CHEMIN — contenu d'un fichier de la branche main.
_m10p_fichier_main() {
  local p="${1//\//%2F}" f="${2//\//%2F}"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m10p_fichier_existe PROJET CHEMIN — le fichier existe sur main (et n'est pas vide).
_m10p_fichier_existe() {
  local c
  c="$(_m10p_fichier_main "$1" "$2" 2>/dev/null)" || return 1
  [[ -n "$c" ]]
}

# _m10p_fichier_contient PROJET CHEMIN REGEX… — le fichier de main contient chaque regex (grep -Ei).
_m10p_fichier_contient() {
  local c r p="$1" f="$2"
  shift 2
  c="$(_m10p_fichier_main "$p" "$f" 2>/dev/null)" || return 1
  for r in "$@"; do grep -Eiq -- "$r" <<<"$c" || return 1; done
}

# _m10p_doc_motif DOSSIER PRÉFIXE — un fichier « PRÉFIXE* » existe dans DOSSIER de plateforme/medisphere (main).
_m10p_doc_motif() {
  local d="${1//\//%2F}"
  gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=$d&per_page=100" 2>/dev/null \
    | jq -e --arg p "$2" 'any(.[]?; .name | startswith($p))' >/dev/null
}

# _m10p_doc_contient DOSSIER PRÉFIXE REGEX… — le premier fichier « PRÉFIXE* » du dossier contient chaque regex.
_m10p_doc_contient() {
  local d="$1" pref="$2" nom
  shift 2
  nom="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=${d//\//%2F}&per_page=100" 2>/dev/null \
    | jq -r --arg p "$pref" '[.[]? | select(.name | startswith($p)) | .name][0] // empty')" || return 1
  [[ -n "$nom" ]] || return 1
  _m10p_fichier_contient plateforme/medisphere "$d/$nom" "$@"
}

# _m10p_pipeline_ok PROJET — dernier pipeline de main réussi (« manual » = réussi avec jobs manuels).
_m10p_pipeline_ok() {
  gitlab_api "projects/${1//\//%2F}/pipelines?ref=main&per_page=1" 2>/dev/null \
    | jq -e '.[0].status == "success" or .[0].status == "manual"' >/dev/null
}

# --- Pannes ---------------------------------------------------------------------------------------

# _m10p_aucune_panne_active — aucune panne M10 marquée active par lab/bin/break.
_m10p_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"
  [[ -z "$(find "$d" -maxdepth 1 -name 'M10-E*' 2>/dev/null)" ]]
}

# _m10p_id TYPE NOM ID_PROJET — identifiant de la ressource NOM du projet (« TYPE list --project »).
# Les recherches par nom d'un administrateur ne sont pas toujours limitées au projet (Cinder,
# Nova) : on passe toujours par l'identifiant. Échoue si absente ou ambiguë.
_m10p_id() {
  local l
  l="$(_m10p_os "$1" list --project "$3")" || return 1
  jq -er --arg n "$2" '[.[] | select(.Name == $n or .name == $n)] | if length == 1 then (.[0].ID // .[0].id) else error("absent ou ambigu") end' <<<"$l"
}
