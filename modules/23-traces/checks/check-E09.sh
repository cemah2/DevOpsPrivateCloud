# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E09.sh — M23-E09 : Échantillonnage en tête et en queue
# Lecture seule : CR des Collectors et charges (kube), dépôts de déploiement (GitLab, GET), métriques internes
# du tail_sampling (Prometheus).

# shellcheck source=_m23-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-operationnel.sh"

title "M23-E09 — Échantillonnage en tête et en queue"
require_cmd jq kubectl curl

# --- 1. En queue : la passerelle -------------------------------------------------------------------------
check_cmd "otel-passerelle : 2 réplicas déclarés et 2 disponibles" _m23d_kq \
  '.spec.replicas == 2 and (.status.availableReplicas // 0) == 2' -n "$_m23d_ns" deployment otel-passerelle-collector
check_cmd "otel-passerelle : tail_sampling dans le pipeline traces, après memory_limiter" bash -c \
  '[[ "$(head -n 1 <<<"$1")" == memory_limiter* ]] && grep -q "^tail_sampling" <<<"$1"' _ "$(_m23d_processeurs otel-passerelle)"
check_cmd "politique « erreurs » : statut ERROR gardé" _m23d_cr otel-passerelle \
  '[.spec.config.processors | to_entries[] | select(.key | startswith("tail_sampling")) | .value.policies[]? | select(.type == "status_code" and ((.status_code.status_codes // []) | index("ERROR") != null))] | length >= 1'
check_cmd "politique « lentes » : seuil de latence de 500 ms" _m23d_cr otel-passerelle \
  '[.spec.config.processors | to_entries[] | select(.key | startswith("tail_sampling")) | .value.policies[]? | select(.type == "latency" and .latency.threshold_ms == 500)] | length >= 1'
check_cmd "politique « reste » : 10 % probabiliste" _m23d_cr otel-passerelle \
  '[.spec.config.processors | to_entries[] | select(.key | startswith("tail_sampling")) | .value.policies[]? | select(.type == "probabilistic" and .probabilistic.sampling_percentage == 10)] | length >= 1'

# --- 2. L'équilibrage par trace : les agents ------------------------------------------------------------------
check_cmd "otel-agent : exportateur loadbalancing, routing_key traceID, dans le pipeline" _m23d_cr otel-agent \
  '([.spec.config.exporters | to_entries[] | select((.key | startswith("loadbalancing")) and (.value.routing_key // "traceID") == "traceID")] | length >= 1) and ([.spec.config.service.pipelines.traces.exporters[] | select(startswith("loadbalancing"))] | length >= 1)'
check_cmd "résolveur vers le Service SANS TÊTE de la passerelle (k8s ou dns)" _m23d_cr otel-agent \
  '[.spec.config.exporters | to_entries[] | select(.key | startswith("loadbalancing")) | .value.resolver | ((.k8s.service // "") + (.dns.hostname // ""))] | any(test("otel-passerelle-collector-headless"))'
check_cmd "plus aucun export direct vers le Service ordinaire de la passerelle" _m23d_cr otel-agent \
  '[.spec.config.service.pipelines.traces.exporters[] as $e | .spec.config.exporters[$e].endpoint? // "" | select(test("otel-passerelle-collector(\\.|:)"))] | length == 0'

# --- 3. En tête : les applications ---------------------------------------------------------------------------
for _m23o_e09_p in mediagenda/deploiement medidoc/deploiement; do
  check_cmd "$_m23o_e09_p : échantillonneur parentbased_traceidratio avec ratio explicite" \
    _m23d_contient "$_m23o_e09_p" components/telemetrie/kustomization.yaml 'parentbased_traceidratio' 'OTEL_TRACES_SAMPLER_ARG'
done

# --- 4. Ça tourne --------------------------------------------------------------------------------------------
check_cmd "décisions d'échantillonnage en queue dans la dernière heure (métriques du tail_sampling)" _m23d_prom_positif \
  'sum(increase({__name__=~"otelcol_processor_tail_sampling_global_count_traces_sampled(_total)?", namespace="traces"}[1h]))'
check_cmd "aucune trace décidée trop tôt (mémoire du tail_sampling suffisante, 1 h)" _m23d_prom_nul \
  'sum(increase({__name__=~"otelcol_processor_tail_sampling_sampling_trace_dropped_too_early(_total)?", namespace="traces"}[1h]))'
check_cmd "plateforme/medisphere : echantillonnage.md" _m23d_contient plateforme/medisphere \
  docs/observabilite/traces/echantillonnage.md 'traceID|traceid' 'erreur' '500'
