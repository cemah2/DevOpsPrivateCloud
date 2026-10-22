# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E28.sh — M21-E28 « Superviser la supervision »
# À lancer depuis adm01. Lecture seule : alertes et cibles du cluster (Thanos Query), configuration
# d'Alertmanager (API v2), Prometheus témoin de mon01 (API HTTP, MGMT → mon01:9090), messages de
# Mailpit (compte de lecture des checks), CR Alertmanager (compte wb-checks).

# shellcheck source=_m21-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-production.sh"

title "M21-E28 — Superviser la supervision"
require_cmd kubectl jq curl yq

title "Côté cluster"
check_output "l'alerte Watchdog est active dans le cluster" '^[1-9]' \
  _m21p_nb 'ALERTS{alertname="Watchdog", alertstate="firing"}'
_m21_e28_am="$(_m21p_am_config | yq -o=json '.' 2>/dev/null || echo null)"
[[ -n "$_m21_e28_am" ]] || _m21_e28_am=null
# Récepteur de la première route dont les matchers visent Watchdog, puis ses intégrations.
_m21_e28_rec="$(jq -r '[.route.routes[]? | select((((.matchers // []) | join(" ")) + ((.match // {}) | tostring)) | test("Watchdog"))][0].receiver // ""' \
  <<<"$_m21_e28_am" 2>/dev/null || true)"
check_cmd "Watchdog a sa route dédiée dans Alertmanager" test -n "$_m21_e28_rec"
if [[ -n "$_m21_e28_rec" ]]; then
  check_cmd "la route de Watchdog n'envoie pas de courriel (récepteur « $_m21_e28_rec »)" _m21p_jq "$_m21_e28_am" \
    'any(.receivers[]; .name == $r) and all(.receivers[] | select(.name == $r); ((.email_configs // []) | length) == 0)' \
    --arg r "$_m21_e28_rec"
fi
_m21_e28_amcr="$(_m21p_json -n "$_M21P_NS" get alertmanagers.monitoring.coreos.com kps)"
check_cmd "l'Alertmanager du cluster est revenu après l'essai (réplicas ≥ 1)" \
  _m21p_jq "$_m21_e28_amcr" '(.spec.replicas // 1) >= 1'
check_output "le cluster collecte le Prometheus témoin (up{job=\"temoin-mon01\"} = 1)" '^1$' \
  _m21p_valeur 'max(up{job="temoin-mon01"})'
_m21_e28_p="$(_m21p_prometheus)"
check_cmd "chemin de secours : Prometheus envoie aussi des alertes à l'Alertmanager témoin (additionalAlertManagerConfigs)" \
  _m21p_jq "$_m21_e28_p" '(.spec.additionalAlertManagerConfigs.name // "") != ""'
_m21_e28_r="$(_m21p_regles alert)"
check_cmd "alerte TemoinInjoignable chargée dans le cluster" _m21p_alerte_chargee TemoinInjoignable "$_m21_e28_r"
check_cmd "TemoinInjoignable couvre aussi l'absence de la cible (absent())" _m21p_jq "$_m21_e28_r" \
  'any(.data.groups[].rules[]; .name == "TemoinInjoignable" and (.query | test("absent\\(")))'

title "Côté témoin (mon01)"
_m21_e28_tr="$(_m21p_temoin "rules?type=alert" || echo null)"
if [[ "$_m21_e28_tr" == null || -z "$_m21_e28_tr" ]]; then
  check_cmd "API du Prometheus témoin ($_M21P_TEMOIN) joignable depuis adm01" false
else
  check_cmd "alerte SupervisionClusterMuette chargée sur le témoin" \
    _m21p_jq "$_m21_e28_tr" 'any(.data.groups[].rules[]; .name == "SupervisionClusterMuette")'
  check_cmd "alerte SupervisionClusterComposantKO chargée sur le témoin" \
    _m21p_jq "$_m21_e28_tr" 'any(.data.groups[].rules[]; .name == "SupervisionClusterComposantKO")'
  _m21_e28_w="$(_m21p_temoin_requete 'probe_success{job="watchdog-cluster"}' | jq -r '[.data.result[].value[1]] | join(",")' 2>/dev/null || true)"
  check_output "la sonde Watchdog du témoin réussit (probe_success = 1)" '^1$' echo "$_m21_e28_w"
  # La sonde doit viser Thanos Query (l'API de requête, pas /federate qu'il ne sert pas).
  _m21_e28_url="$(_m21p_temoin "targets?state=active" \
    | jq -r '[.data.activeTargets[] | select(.labels.job == "watchdog-cluster") | .scrapeUrl] | first // ""' 2>/dev/null || true)"
  check_output "la sonde Watchdog interroge l'API de requête de 10.10.41.60 (prometheus.apps…:9090/api/v1/query)" \
    'target=http%3A%2F%2F(prometheus\.apps\.par1\.medisphere\.internal|10\.10\.41\.60)%3A9090%2Fapi%2Fv1%2Fquery' \
    echo "$_m21_e28_url"
  _m21_e28_s="$(_m21p_temoin_requete 'probe_success{job="supervision-cluster"}' \
    | jq -r '[.data.result[] | select(.value[1] == "1")] | length' 2>/dev/null || echo 0)"
  check_output "sondes /-/healthy et /-/ready de Thanos Query et d'Alertmanager en succès (4)" '^([4-9]|[1-9][0-9])$' \
    echo "$_m21_e28_s"
fi

title "Essai : Alertmanager du cluster arrêté"
_m21_e28_mail="$(mailpit_api "search?query=SupervisionClusterComposantKO" 2>/dev/null | jq -r '.messages_count // 0' 2>/dev/null || echo 0)"
check_output "courriel du témoin reçu dans Mailpit (SupervisionClusterComposantKO)" '^[1-9]' echo "$_m21_e28_mail"
check_cmd "runbook RB-215 dans $_M21P_DOC (docs/observabilite/metriques/runbooks/)" \
  _m21p_doc_present "$_M21P_DOC" docs/observabilite/metriques/runbooks 'RB-215[^/]*\.md$' 20
