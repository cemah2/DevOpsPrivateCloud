# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E13.sh — M23-E13 « Métriques tirées des traces : graphes de services et RED ». Lecture seule.

# shellcheck source=_m23-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-production.sh"

title "M23-E13 — Métriques tirées des traces"
require_cmd kubectl jq yq curl

check_cmd "Prometheus kps-prometheus : récepteur d'écriture distante activé (enableRemoteWriteReceiver)" \
  _m23p_kq '.spec.enableRemoteWriteReceiver == true' -n supervision prometheuses.monitoring.coreos.com kps-prometheus
check_cmd "Tempo : metrics_generator avec au moins une cible remote_write" \
  _m23p_tempo_conf_jq '(.metrics_generator.storage.remote_write // []) | length >= 1'
check_cmd "Tempo : remote_write vers chaque réplica de Prometheus (2 cibles distinctes)" \
  _m23p_tempo_conf_jq '[.metrics_generator.storage.remote_write[]?.url] | unique | length >= 2'
check_cmd "Tempo : exemplars envoyés (send_exemplars) sur chaque cible" \
  _m23p_tempo_conf_jq '[.metrics_generator.storage.remote_write[]? | .send_exemplars == true] | length > 0 and all'
check_cmd "Tempo : processeurs service-graphs et span-metrics activés (overrides.defaults)" \
  _m23p_tempo_conf_jq '(.overrides.defaults.metrics_generator.processors // []) as $p | ($p | index("service-graphs")) != null and ($p | index("span-metrics")) != null'
check_cmd "Tempo : cardinalité bornée (overrides.defaults.metrics_generator.max_active_series > 0)" \
  _m23p_tempo_conf_jq '(.overrides.defaults.metrics_generator.max_active_series // 0) > 0'

for _m23_e13_s in mediagenda-api medidoc; do
  check_cmd "série traces_spanmetrics_calls_total{service=\"$_m23_e13_s\"} présente (5 dernières minutes)" \
    _m23p_prom_present "sum by (service) (increase(traces_spanmetrics_calls_total{service=\"$_m23_e13_s\"}[5m]))"
done
check_cmd "histogramme traces_spanmetrics_latency_bucket présent pour mediagenda-api" \
  _m23p_prom_present 'sum by (le) (rate(traces_spanmetrics_latency_bucket{service="mediagenda-api"}[5m]))'
check_cmd "graphe de services : arête mediagenda-api → medidoc (traces_service_graph_request_total)" \
  _m23p_prom_present 'sum(increase(traces_service_graph_request_total{client="mediagenda-api", server="medidoc"}[15m])) > 0'
check_cmd "graphe de services : arête vers la base de données de MédiAgenda (nœud virtuel)" \
  _m23p_prom_present 'sum by (server) (increase(traces_service_graph_request_total{client="mediagenda-api", server!="medidoc"}[15m])) > 0'

_m23_e13_tempo="$(_m23p_ds tempo)" || _m23_e13_tempo=""
check_cmd "source Grafana Tempo : graphe de services relié à Prometheus (serviceMap.datasourceUid)" \
  jq -e '(.jsonData.serviceMap.datasourceUid // "") != ""' <<<"${_m23_e13_tempo:-null}"

_m23_e13_tableau() {
  grafana_api "dashboards/uid/m23-red-traces" 2>/dev/null |
    jq -e '(.dashboard | tostring) as $d | ($d | test("traces_spanmetrics")) and ($d | test("mediagenda_http_request"))' >/dev/null 2>&1
}
check_cmd "tableau « MédiAgenda — RED depuis les traces » (UID m23-red-traces) : spanmetrics ET métriques applicatives" _m23_e13_tableau
check_cmd "plateforme/observabilite : tableau versionné dans tableaux/" \
  _m23p_depot_contient plateforme/observabilite tableaux '"uid": *"m23-red-traces"'
check_cmd "docs/observabilite/traces/metriques-depuis-traces.md : écart avec les métriques applicatives et cardinalité expliqués" \
  _m23p_doc docs/observabilite/traces metriques-depuis-traces 'chantillonnage' 'cardinalit' 'mediagenda_http_request'
