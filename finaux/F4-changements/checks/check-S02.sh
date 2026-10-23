# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S02.sh — F4-S02 « La sonde de continuité » : sondes de continuité de mon01 actives (vues par le
# témoin et fédérées), règles d'enregistrement de la mesure (témoin et cluster), tableau Grafana
# « changement en cours », charge k6 définie dans plateforme/resilience et déjà passée par Prometheus,
# documentation. Lecture seule.

# shellcheck source=_f4-montees.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-montees.sh"

title "F4-S02 — La sonde de continuité"
require_cmd curl jq yq

title "Sondes de mon01"
_f4_s02_services() {
  _f4m_prom temoin 'count by (service) (probe_success{job="blackbox", groupe=~"continuite-.+"})' 2>/dev/null |
    jq -r '.data.result[].metric.service // empty' 2>/dev/null | sort -u
}
_f4_s02_liste="$(_f4_s02_services || true)"
for _f4_s02_s in mediagenda medidoc rabbitmq portail; do
  check_cmd "témoin : une sonde de continuité étiquetée service=$_f4_s02_s" grep -qx "$_f4_s02_s" <<<"$_f4_s02_liste"
done
for _f4_s02_s in legacy-rdv openstack; do
  if grep -qx "$_f4_s02_s" <<<"$_f4_s02_liste"; then
    _ok "témoin : sonde de continuité service=$_f4_s02_s présente"
  else
    skip "sonde service=$_f4_s02_s" "ajoutée quand le service existe dans le lab (S08 pour openstack, S10 pour legacy-rdv)"
  fi
done
check_cmd "témoin : les sondes MédiAgenda et portail réussissent en ce moment" _f4m_prom_non_vide temoin \
  'min by () (probe_success{job="blackbox", groupe=~"continuite-.+", service=~"mediagenda|portail"}) == 1'

title "Mesure de l'interruption"
check_cmd "témoin : série enregistrée continuite:sondes_en_erreur:max présente" _f4m_prom_non_vide temoin 'continuite:sondes_en_erreur:max'
check_cmd "cluster : séries de continuité fédérées depuis mon01 (continuite:sondes_en_erreur:max)" _f4m_prom_non_vide cluster \
  'continuite:sondes_en_erreur:max'
check_cmd "cluster : série enregistrée continuite:en_erreur présente (règle évaluée)" _f4m_prom_non_vide cluster 'continuite:en_erreur'
if _f4m_api_repond; then
  check_cmd "PrometheusRule « continuite » (supervision) : règle continuite:en_erreur à 15 s" _f4m_kq \
    'any(.spec.groups[]; (.interval // "") == "15s" and any(.rules[]; .record == "continuite:en_erreur"))' \
    -n supervision prometheusrules.monitoring.coreos.com continuite
else
  skip "PrometheusRule continuite" "l'API ne répond pas au compte des checks"
fi
_f4_s02_tests() {
  local f
  while IFS= read -r f; do
    [[ "$f" =~ \.ya?ml$ ]] || continue
    _f4m_contient "$_f4m_observabilite" "$f" 'continuite:en_erreur' 'promql_expr_test|alert_rule_test' && return 0
  done < <(_f4m_arbre "$_f4m_observabilite" tests)
  return 1
}
check_cmd "plateforme/observabilite tests/ (main) : test promtool de continuite:en_erreur" _f4_s02_tests

title "Tableau « changement en cours »"
_f4_s02_tableau() {
  grafana_api "dashboards/uid/$_f4m_tableau" 2>/dev/null | jq -e '(.dashboard | tostring) as $t
    | ($t | test("continuite:en_erreur")) and ($t | test("probe_success|continuite:sonde_en_erreur"))
    and ($t | test("histogram_quantile\\(0\\.9[59]|p9[59]")) and ($t | test("pyrra|slo"; "i"))' >/dev/null 2>&1
}
check_cmd "Grafana : tableau $_f4m_tableau (erreurs, latence p95/p99, sondes, budget d'erreur)" _f4_s02_tableau

title "Charge constante (k6)"
_f4_s02_docs="$(
  {
    while IFS= read -r f; do
      [[ "$f" =~ \.ya?ml$ ]] || continue
      _f4m_fichier "$_f4m_resilience" "$f" 2>/dev/null | yq -o=json -I=0 'select(. != null)' 2>/dev/null
    done < <(_f4m_arbre "$_f4m_resilience" continuite)
  } | jq -s '.' 2>/dev/null
)" || true
[[ -n "$_f4_s02_docs" ]] || _f4_s02_docs='[]'
_f4_s02_testrun() {
  jq -e 'any(.[]; .kind == "TestRun" and (.spec.script.configMap.name // "") != ""
    and ((.spec.arguments // "") | test("testid=sonde-continuite"))
    and ((.spec.runner.image // "") | startswith("registry.par1.medisphere.internal/")))' >/dev/null 2>&1 <<<"$_f4_s02_docs"
}
check_cmd "plateforme/resilience continuite/ (main) : un TestRun de la sonde (testid sonde-continuite…, image Harbor)" _f4_s02_testrun
_f4_s02_script() {
  local f
  f="$(_f4m_chemin "$_f4m_resilience" continuite '\.js$')" || return 1
  _f4m_contient "$_f4m_resilience" "$f" 'mediagenda\.apps' 'mediagenda-recette' 'constant-arrival-rate'
}
check_cmd "plateforme/resilience continuite/ : script k6 de la sonde (lecture en prod, écriture en recette)" _f4_s02_script
check_cmd "Prometheus : la charge de la sonde a envoyé des requêtes (7 derniers jours)" _f4m_prom_non_vide cluster \
  'sum(increase(k6_http_reqs_total{testid=~"sonde-continuite.*"}[7d])) > 0'

title "Documentation"
check_cmd "sonde-continuite.md : objectifs, sondes, mesure (PromQL), mode d'emploi" \
  _f4m_doc . '^sonde-continuite\.md$' 'continuite:en_erreur' 'avg_over_time' 'mon01' 'k6'
check_cmd "RB-340 publié : lancer et arrêter la sonde, relever la mesure" _f4m_doc runbooks '^RB-340' 'testid' 'mesure'
