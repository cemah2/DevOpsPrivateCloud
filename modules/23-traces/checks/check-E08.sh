# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq, LogQL et PromQL entre apostrophes
#
# check-E08.sh — M23-E08 : Corrélation : exemplars, trace_id dans les journaux, liens Grafana
# Lecture seule : Loki (GET, locataires mediagenda et medidoc), sources Grafana (ConfigMaps du sidecar),
# CR Prometheus (kube), API des exemplars de Prometheus/Thanos Query (GET), dépôts GitLab (GET).

# shellcheck source=_m23-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-operationnel.sh"

title "M23-E08 — Corrélation : exemplars, trace_id dans les journaux, liens Grafana"
require_cmd jq kubectl curl

# --- 1. Journaux -------------------------------------------------------------------------------------
check_cmd "mediagenda/api (main) : trace_id et span_id dans le format JSON (journal.py)" \
  _m23d_contient mediagenda/api src/mediagenda/journal.py 'trace_id' 'span_id'
_m23o_e08_medidoc_trace_id() {
  local f
  for f in $(_m23d_arbre medidoc/medidoc internal); do
    [[ "$f" == *.go && "$f" != *_test.go ]] || continue
    if _m23d_fichier medidoc/medidoc "$f" 2>/dev/null | grep -q '"trace_id"'; then return 0; fi
  done
  return 1
}
check_cmd "medidoc/medidoc (main) : trace_id et span_id ajoutés par le gestionnaire slog" _m23o_e08_medidoc_trace_id
check_cmd "Loki (mediagenda) : lignes de mediagenda-dev avec la métadonnée structurée trace_id (1 h)" \
  _m23o_loki_flux mediagenda '{namespace="mediagenda-dev"} | trace_id != ""'
check_cmd "Loki (medidoc) : lignes de medidoc-dev avec la métadonnée structurée trace_id (1 h)" \
  _m23o_loki_flux medidoc '{namespace="medidoc-dev"} | trace_id != ""'
_m23o_e08_pas_etiquette() {
  local r
  r="$(loki_api "labels" mediagenda 2>/dev/null)" || return 1
  jq -e '(.data // []) | index("trace_id") == null' >/dev/null 2>&1 <<<"$r"
}
check_cmd "trace_id n'est PAS une étiquette Loki (liste fermée du M22)" _m23o_e08_pas_etiquette

# --- 2. Sources Grafana --------------------------------------------------------------------------------
_M23O_E08_SRC="$(_m23d_sources_grafana)"
check_cmd "Loki → Tempo : champ dérivé sur l'étiquette trace_id vers la source tempo" bash -c \
  'grep -q "derivedFields" <<<"$1" && grep -Eq "matcherType: *\"?label" <<<"$1" && grep -Eq "datasourceUid: *\"?tempo" <<<"$1"' _ "$_M23O_E08_SRC"
check_cmd "Tempo → Loki : tracesToLogsV2 vers une source Loki" bash -c \
  'grep -A3 "tracesToLogsV2" <<<"$1" | grep -Eq "datasourceUid: *\"?loki"' _ "$_M23O_E08_SRC"
check_cmd "Prometheus → Tempo : exemplarTraceIdDestinations (étiquette trace_id) sur la source Prometheus" bash -c \
  'grep -A3 "exemplarTraceIdDestinations" <<<"$1" | grep -Eq "datasourceUid: *\"?tempo" && grep -A3 "exemplarTraceIdDestinations" <<<"$1" | grep -q "trace_id"' _ "$_M23O_E08_SRC"

# --- 3. Exemplars --------------------------------------------------------------------------------------
check_cmd "Prometheus : stockage des exemplars activé (enableFeatures exemplar-storage)" _m23d_kq \
  '[.items[] | select((.spec.enableFeatures // []) | index("exemplar-storage") != null)] | length >= 1' \
  -n supervision prometheuses.monitoring.coreos.com
_m23o_e08_rc=0
_m23o_exemplars 'mediagenda_http_request_duration_seconds_bucket' 3600 || _m23o_e08_rc=$?
case "$_m23o_e08_rc" in
  0) check_cmd "exemplars trace_id sur l'histogramme de MédiAgenda (1 h)" true ;;
  2) skip "exemplars de MédiAgenda" "API query_exemplars injoignable ou refusée : interroge-la sur un pod Prometheus (corrigé)" ;;
  *) check_cmd "exemplars trace_id sur l'histogramme de MédiAgenda (1 h)" false ;;
esac
check_cmd "plateforme/medisphere : correlation.md" _m23d_contient plateforme/medisphere \
  docs/observabilite/traces/correlation.md 'exemplar' 'trace_id' 'Loki'
