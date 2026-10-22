# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E26.sh — M21-E26 « SLI et SLO de MédiAgenda avec Pyrra »
# À lancer depuis adm01. Lecture seule : Deployments, CR ServiceLevelObjective (pyrra.dev, ClusterRole
# wb-checks-observabilite) et PrometheusRule générées (compte wb-checks), règles chargées (Thanos
# Query), interface https://slo.apps… (GET).

# shellcheck source=_m21-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-production.sh"

title "M21-E26 — SLI et SLO de MédiAgenda avec Pyrra"
require_cmd kubectl jq curl

for _m21_e26_d in pyrra-kubernetes pyrra-api; do
  _m21_e26_o="$(_m21p_json -n "$_M21P_NS" get deployment "$_m21_e26_d")"
  check_cmd "$_m21_e26_d : prêt, image v0.10.x tirée par Harbor" _m21p_jq "$_m21_e26_o" \
    '(.status.readyReplicas // 0) >= 1 and any(.spec.template.spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/.*pyrra:v0\\.10\\."))'
done
_m21_e26_api="$(_m21p_json -n "$_M21P_NS" get deployment pyrra-api)"
check_cmd "pyrra-api interroge Thanos Query (fenêtre de 28 jours au-delà de la rétention locale)" \
  _m21p_jq "$_m21_e26_api" 'any(.spec.template.spec.containers[].args[]?; test("^--prometheus-url=http://thanos-query"))'
check_http "interface https://slo.apps.par1.medisphere.internal" "$_M21P_SLO_URL/" 200

title "Objectifs (ServiceLevelObjective)"
_m21_e26_slos="$(_m21p_json -n "$_M21P_NS" get servicelevelobjectives.pyrra.dev)"
_m21_e26_slo_ok() {
  _m21p_jq "$_m21_e26_slos" 'any(.items[]; .metadata.name == $n and .spec.target == $t and .spec.window == "28d")' \
    --arg n "$1" --arg t "$2"
}
check_cmd "mediagenda-disponibilite : 99.5 sur 28d" _m21_e26_slo_ok mediagenda-disponibilite 99.5
check_cmd "mediagenda-latence : 95 sur 28d" _m21_e26_slo_ok mediagenda-latence 95
check_cmd "medidoc-disponibilite : objectif sur 28d" \
  _m21p_jq "$_m21_e26_slos" 'any(.items[]; .metadata.name == "medidoc-disponibilite" and .spec.window == "28d")'
check_cmd "les SLO de MédiAgenda portent sur la production et excluent les sondes" _m21p_jq "$_m21_e26_slos" '
  [.items[] | select(.metadata.name | startswith("mediagenda-")) | .spec.indicator | tostring]
  | length == 2 and all(.[]; test("mediagenda-prod") and test("sante"))'
check_cmd "le SLO de latence compte un seau existant de l'histogramme (le=\"0.25\" ou \"0.3\")" _m21p_jq "$_m21_e26_slos" '
  any(.items[]; .metadata.name == "mediagenda-latence"
      and (.spec.indicator.latency.success.metric | test("le=\"(0\\.25|0\\.3)\"")))'

title "Règles générées par Pyrra"
_m21_e26_pr="$(_m21p_json -n "$_M21P_NS" get prometheusrules.monitoring.coreos.com)"
_m21_e26_r="$(_m21p_regles record)"
for _m21_e26_s in mediagenda-disponibilite mediagenda-latence medidoc-disponibilite; do
  check_cmd "PrometheusRule $_m21_e26_s produite par Pyrra (propriétaire : le SLO)" _m21p_jq "$_m21_e26_pr" \
    'any(.items[]; .metadata.name == $n and any(.metadata.ownerReferences[]?; .kind == "ServiceLevelObjective"))' --arg n "$_m21_e26_s"
  check_cmd "groupes de règles de $_m21_e26_s chargés par Prometheus" _m21p_groupe_charge "$_m21_e26_s" "$_m21_e26_r"
done
check_cmd "les PrometheusRule de Pyrra portent l'étiquette de sélection de Prometheus" _m21p_jq "$_m21_e26_pr" '
  [.items[] | select(any(.metadata.ownerReferences[]?; .kind == "ServiceLevelObjective"))]
  | length >= 3 and all(.[]; .metadata.labels["medisphere.internal/supervision"] == "oui")'
