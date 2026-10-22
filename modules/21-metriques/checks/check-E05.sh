# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas du shell)
#
# check-E05.sh — M21-E05 : Grafana : sources de données, exploration, premier tableau de bord
# À lancer depuis adm01. Lecture seule : API HTTP de Grafana avec le jeton du compte de service
# wb-checks (Viewer, ~/.config/workbook/grafana-checks.token), GET seulement.

# shellcheck source=_m21-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-decouverte.sh"

title "M21-E05 — Grafana : sources de données, exploration, premier tableau de bord"
require_cmd jq curl

_m21d_e05_jeton="${WB_GRAFANA_TOKEN_FILE:-$HOME/.config/workbook/grafana-checks.token}"
check_cmd "Jeton des checks : $_m21d_e05_jeton présent, lisible par toi seul (600)" bash -c \
  '[[ -r "$1" && "$(stat -c %a "$1")" == "600" && -s "$1" ]]' _ "$_m21d_e05_jeton"
if [[ ! -r "$_m21d_e05_jeton" ]]; then
  skip "Contrôles par l'API de Grafana" "jeton absent : crée le compte de service wb-checks (étape 7 de l'énoncé)"
  return 0
fi

# --- 1. Le jeton fonctionne et n'a que des droits de lecture -----------------------------------------
_m21d_e05_recherche="$(grafana_api "search?type=dash-db&limit=500" 2>/dev/null || true)"
check_cmd "Le jeton wb-checks est accepté par Grafana (recherche de tableaux)" _m21d_json "$_m21d_e05_recherche" 'type == "array"'
# Un Viewer ne liste pas les sources de données (action datasources:read, réservée aux
# administrateurs de l'organisation) : un jeton qui le peut a trop de droits.
_m21d_e05_trop_de_droits() {
  grafana_api "datasources" >/dev/null 2>&1
}
if _m21d_e05_trop_de_droits; then
  _ko "Le jeton wb-checks liste les sources de données : son rôle dépasse Viewer"
else
  _ok "Le jeton wb-checks ne liste pas les sources de données (rôle Viewer)"
fi

# --- 2. La source de données Prometheus ------------------------------------------------------------
_m21d_e05_sante="$(grafana_api "datasources/uid/prometheus/health" 2>/dev/null || true)"
if [[ -z "$_m21d_e05_sante" ]]; then
  skip "Santé de la source Prometheus" "réponse vide ou refusée au rôle Viewer : vérifie-la dans Connections > Data sources > Prometheus > Test"
else
  check_cmd "Source de données « prometheus » saine (test de connexion de Grafana)" _m21d_json "$_m21d_e05_sante" \
    '.status == "OK"'
fi

# --- 3. Le tableau de bord ---------------------------------------------------------------------------
check_cmd "Tableau « MédiAgenda — aperçu » présent, rangé dans le dossier « MédiAgenda »" _m21d_json "$_m21d_e05_recherche" \
  '[.[] | select(.title == "MédiAgenda — aperçu" and .folderTitle == "MédiAgenda")] | length == 1'
_m21d_e05_uid="$(jq -r '[.[] | select(.title == "MédiAgenda — aperçu")][0].uid // empty' <<<"$_m21d_e05_recherche" 2>/dev/null || true)"
_m21d_e05_tdb=""
[[ -n "$_m21d_e05_uid" ]] && _m21d_e05_tdb="$(grafana_api "dashboards/uid/$_m21d_e05_uid" 2>/dev/null || true)"
if ! _m21d_json "$_m21d_e05_tdb" '.dashboard.panels | type == "array"'; then
  skip "Contenu du tableau" "modèle classique illisible par /api/dashboards/uid (tableau enregistré au schéma v2 ?) : contrôle-le à l'écran"
else
  # Panneaux à plat (ceux des rangées repliées compris), puis toutes leurs expressions.
  _m21d_e05_expr="$(jq -r '[.dashboard.panels[] | ., (.panels[]?)] | .[] | .targets[]?.expr // empty' <<<"$_m21d_e05_tdb")"
  check_cmd "Au moins 4 panneaux" _m21d_json "$_m21d_e05_tdb" '[.dashboard.panels[] | ., (.panels[]?) | select(.type != "row")] | length >= 4'
  check_output "Un panneau de débit (rate sur mediagenda_http_requests_total)" \
    'rate\(mediagenda_http_requests_total' printf '%s' "$_m21d_e05_expr"
  check_output "Un panneau de latence (histogram_quantile sur l'histogramme de MédiAgenda)" \
    'histogram_quantile\(.*mediagenda_http_request_duration_seconds_bucket' printf '%s' "$_m21d_e05_expr"
  check_output "Les requêtes suivent la variable d'environnement (\$environnement ou \${environnement})" \
    '\$\{?environnement' printf '%s' "$_m21d_e05_expr"
  check_cmd "Variable de tableau « environnement » (espaces de MédiAgenda)" _m21d_json "$_m21d_e05_tdb" \
    '[.dashboard.templating.list[]? | select(.name == "environnement")] | length == 1'
fi
