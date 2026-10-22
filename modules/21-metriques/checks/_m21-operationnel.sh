# shellcheck shell=bash
# _m21-operationnel.sh — fonctions partagées par les checks M21-E10 à M21-E23 (lecture seule).
# Sourcé par les check-EXX.sh du palier 2 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m21o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - Prometheus du cluster : prom_api / prom_requete (WB_PROM_URL) ; Alertmanager : am_api ;
#   - Prometheus et Alertmanager TÉMOINS de mon01 : curl en GET (WB_M21_TEMOIN_URL,
#     WB_M21_TEMOIN_AM_URL), depuis adm01 (MGMT → mon01 9090/9093, M19) ;
#   - cluster : « kube » (compte wb-checks : CRD de prometheus-operator par wb-checks-observabilite,
#     Argo CD et Argo Rollouts par wb-checks-livraison) ;
#   - Grafana : grafana_api (compte de service wb-checks, Viewer) ; Mailpit : mailpit_api ;
#   - GitLab : gitlab_api (jeton read_api) ;
#   - SSH « admin » vers mon01 (WB_M21_MON01) et « root » vers pve01 (WB_PVE_HOST) : commandes
#     de consultation seulement (systemctl is-active, ss, pveum … list).
#
# Variables de lab/lab.env (valeurs par défaut ci-dessous) :
#   WB_M21_MON01          hôte SSH de mon01 (mon01)
#   WB_M21_TEMOIN_URL     Prometheus témoin (http://mon01.par1.medisphere.internal:9090)
#   WB_M21_TEMOIN_AM_URL  Alertmanager témoin (http://mon01.par1.medisphere.internal:9093)

_M21O_NS=supervision
_M21O_MON01="${WB_M21_MON01:-mon01}"
_M21O_TEMOIN="${WB_M21_TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"
_M21O_TEMOIN_AM="${WB_M21_TEMOIN_AM_URL:-http://mon01.par1.medisphere.internal:9093}"
_M21O_P_OBS="plateforme/observabilite"
_M21O_P_ANSIBLE="plateforme/ansible"
_M21O_P_DOC="plateforme/medisphere"
_M21O_P_INFRA="plateforme/infra"
_M21O_P_K8S="plateforme/k8s"
_M21O_P_DEPLOIEMENT="mediagenda/deploiement"
_M21O_TRAVAIL="$HOME/m21"

# _m21o_k ARGS… — kubectl en lecture par le compte des checks (sortie vide en cas d'erreur).
_m21o_k() { kube "$@" 2>/dev/null || true; }

# _m21o_json JSON [--arg NOM VALEUR]… FILTRE_JQ — OK si le filtre jq (-e), DERNIER argument, est
#   vrai sur le JSON donné ; les arguments intermédiaires sont passés à jq (--arg…).
_m21o_json() {
  local donnees="$1"
  shift
  local filtre="${*: -1}"
  local -a options=("${@:1:$#-1}")
  [[ -n "$donnees" ]] && jq -e "${options[@]}" "$filtre" <<<"$donnees" >/dev/null 2>&1
}

# _m21o_uri TEXTE — encodage pour une URL.
_m21o_uri() { jq -rn --arg v "$1" '$v | @uri'; }

# _m21o_fichier PROJET CHEMIN [BRANCHE=main] — le fichier existe sur la branche.
_m21o_fichier() {
  gitlab_api "projects/$(_m21o_uri "$1")/repository/files/$(_m21o_uri "$2")?ref=$(_m21o_uri "${3:-main}")" >/dev/null 2>&1
}

# _m21o_contenu PROJET CHEMIN [BRANCHE=main] — contenu brut (vide si absent).
_m21o_contenu() {
  gitlab_api "projects/$(_m21o_uri "$1")/repository/files/$(_m21o_uri "$2")/raw?ref=$(_m21o_uri "${3:-main}")" 2>/dev/null || true
}

# _m21o_arbre PROJET CHEMIN [BRANCHE=main] — fichiers sous CHEMIN (récursif, un par ligne).
_m21o_arbre() {
  gitlab_api "projects/$(_m21o_uri "$1")/repository/tree?ref=$(_m21o_uri "${3:-main}")&recursive=true&per_page=100&path=$(_m21o_uri "$2")" 2>/dev/null \
    | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
}

# _m21o_branche PROJET BRANCHE — la branche existe.
_m21o_branche() {
  gitlab_api "projects/$(_m21o_uri "$1")/repository/branches/$(_m21o_uri "$2")" >/dev/null 2>&1
}

# _m21o_pipeline PROJET [BRANCHE=main] — JSON du dernier pipeline de la branche (vide si aucun).
_m21o_pipeline() {
  gitlab_api "projects/$(_m21o_uri "$1")/pipelines?ref=$(_m21o_uri "${2:-main}")&per_page=1" 2>/dev/null \
    | jq -c '.[0] // empty' 2>/dev/null || true
}

# _m21o_pipeline_ok PROJET [BRANCHE=main] — le dernier pipeline de la branche a réussi.
_m21o_pipeline_ok() {
  _m21o_json "$(_m21o_pipeline "$1" "${2:-main}")" '.status == "success"'
}

# _m21o_job_ok PROJET JOB [BRANCHE=main] — le dernier pipeline de la branche contient le job JOB,
#   réussi (le job existe donc bien dans la CI, et il passe).
_m21o_job_ok() {
  local id
  id="$(jq -r '.id // empty' <<<"$(_m21o_pipeline "$1" "${3:-main}")" 2>/dev/null || true)"
  [[ -n "$id" ]] || return 1
  gitlab_api "projects/$(_m21o_uri "$1")/pipelines/$id/jobs?per_page=100" 2>/dev/null \
    | jq -e --arg j "$2" 'any(.[]; .name == $j and .status == "success")' >/dev/null 2>&1
}

# _m21o_valeur 'PromQL' — première valeur du résultat (vide si pas de résultat ou erreur).
_m21o_valeur() {
  prom_requete "$1" 2>/dev/null | jq -r 'if .status == "success" then (.data.result[0].value[1] // empty) else empty end' 2>/dev/null || true
}

# _m21o_nb 'PromQL' — nombre de séries du résultat (0 si vide ou erreur).
_m21o_nb() {
  local n
  n="$(prom_requete "$1" 2>/dev/null | jq -r 'if .status == "success" then (.data.result | length) else 0 end' 2>/dev/null || true)"
  echo "${n:-0}"
}

# _m21o_au_moins 'PromQL' N — la première valeur du résultat est >= N.
_m21o_au_moins() {
  local v
  v="$(_m21o_valeur "$1")"
  [[ -n "$v" ]] && awk -v v="$v" -v n="$2" 'BEGIN { exit !(v + 0 >= n + 0) }'
}

# _m21o_vide 'PromQL' — la requête réussit et ne renvoie AUCUNE série.
_m21o_vide() {
  prom_requete "$1" 2>/dev/null | jq -e '.status == "success" and (.data.result | length) == 0' >/dev/null 2>&1
}

# _m21o_job_up JOB N — le job a au moins N cibles, toutes up == 1.
_m21o_job_up() {
  local job="$1" n="$2"
  _m21o_au_moins "count(up{job=\"$job\"})" "$n" && _m21o_vide "up{job=\"$job\"} == 0"
}

# _m21o_regles [TYPE] — JSON de /api/v1/rules du Prometheus du cluster (type=record|alert).
_m21o_regles() {
  prom_api "rules${1:+?type=$1}" 2>/dev/null || true
}

# _m21o_temoin CHEMIN — GET sur l'API du Prometheus témoin (ex. « query?query=up »).
_m21o_temoin() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" "$_M21O_TEMOIN/api/v1/$1" 2>/dev/null || true
}

# _m21o_temoin_requete 'PromQL' — requête instantanée au témoin (JSON).
_m21o_temoin_requete() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" --data-urlencode "query=$1" \
    "$_M21O_TEMOIN/api/v1/query" 2>/dev/null || true
}

# _m21o_temoin_au_moins 'PromQL' N — première valeur du résultat du témoin >= N.
_m21o_temoin_au_moins() {
  local v
  v="$(jq -r 'if .status == "success" then (.data.result[0].value[1] // empty) else empty end' <<<"$(_m21o_temoin_requete "$1")" 2>/dev/null || true)"
  [[ -n "$v" ]] && awk -v v="$v" -v n="$2" 'BEGIN { exit !(v + 0 >= n + 0) }'
}

# _m21o_temoin_vide 'PromQL' — la requête au témoin réussit et ne renvoie aucune série.
_m21o_temoin_vide() {
  jq -e '.status == "success" and (.data.result | length) == 0' <<<"$(_m21o_temoin_requete "$1")" >/dev/null 2>&1
}

# _m21o_am_config — configuration chargée par l'Alertmanager du cluster, en JSON (yq).
_m21o_am_config() {
  am_api "status" 2>/dev/null | jq -r '.config.original // empty' 2>/dev/null | yq -o=json '.' 2>/dev/null || true
}

# _m21o_tableau UID — tableau Grafana (JSON de /api/dashboards/uid, vide si invisible).
_m21o_tableau() {
  grafana_api "dashboards/uid/$(_m21o_uri "$1")" 2>/dev/null || true
}
