# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E02.sh — M23-E02 : L'opérateur OpenTelemetry et le Collector
# Lecture seule : Applications Argo CD, CR OpenTelemetryCollector, Services, politiques (kube) ; métriques
# internes des Collectors (Prometheus) ; port 4317 de 10.10.41.63 depuis adm01 ; dépôts GitLab en GET.
# Rejouable après M23-E03 et suivants (exportateur debug retiré, passerelle à 2 réplicas…).

# shellcheck source=_m23-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-decouverte.sh"

title "M23-E02 — L'opérateur OpenTelemetry et le Collector"
require_cmd jq kubectl curl

# --- 1. L'opérateur ----------------------------------------------------------------------------------
check_cmd "Application Argo CD opentelemetry-operator : Synced et Healthy" _m23d_app_saine opentelemetry-operator
check_cmd "opérateur prêt dans opentelemetry-operator-system (image de Harbor, 0.16x)" _m23d_kq \
  '[.items[] | select((.status.availableReplicas // 0) >= 1 and (.spec.template.spec.containers[0].image | test("^registry\\.par1\\.medisphere\\.internal/.+opentelemetry-operator:0\\.16[0-9]\\.")))] | length >= 1' \
  -n opentelemetry-operator-system deployments
check_cmd "CRD OpenTelemetryCollector servie en v1beta1" _m23d_kq \
  '[.spec.versions[] | select(.name == "v1beta1" and .served)] | length == 1' crd opentelemetrycollectors.opentelemetry.io
check_output "plateforme/charts-miroir (main) : chart opentelemetry-operator recopié" 'opentelemetry-operator' \
  _m23d_fichier plateforme/charts-miroir charts.yaml

# --- 2. Les Collectors ------------------------------------------------------------------------------------
check_cmd "Application Argo CD otel : Synced et Healthy" _m23d_app_saine otel
check_cmd "otel-agent : mode daemonset, compte otel-agent, image contrib de Harbor 0.16x" _m23d_cr otel-agent \
  '.spec.mode == "daemonset" and .spec.serviceAccount == "otel-agent" and (.spec.image | test($re))' --arg re "$_m23d_re_image"
check_cmd "otel-passerelle : mode deployment, image contrib de Harbor 0.16x" _m23d_cr otel-passerelle \
  '.spec.mode == "deployment" and (.spec.image | test($re))' --arg re "$_m23d_re_image"
check_cmd "otel-agent : un pod prêt par travailleur" _m23d_collector_pret otel-agent
check_cmd "otel-passerelle : pod(s) prêt(s)" _m23d_collector_pret otel-passerelle
for _m23d_e02_c in otel-agent otel-passerelle; do
  check_cmd "$_m23d_e02_c : memory_limiter EN PREMIER dans le pipeline traces" bash -c \
    '[[ "$(head -n 1 <<<"$1")" == memory_limiter* ]]' _ "$(_m23d_processeurs "$_m23d_e02_c")"
  check_cmd "$_m23d_e02_c : récepteur OTLP gRPC ouvert au pod (pas sur localhost)" _m23d_cr "$_m23d_e02_c" \
    '.spec.config.receivers.otlp.protocols.grpc.endpoint | test("^(0\\.0\\.0\\.0|\\[::\\]|\\$\\{env:[A-Z_]+\\}):4317$")'
  check_cmd "$_m23d_e02_c : exportateurs nommés otlp_grpc/otlp_http (pas les alias dépréciés otlp, otlphttp)" _m23d_cr "$_m23d_e02_c" \
    '[.spec.config.exporters | keys[] | select(test("^(otlp|otlphttp)(/|$)"))] | length == 0'
  check_cmd "$_m23d_e02_c : aucun exportateur debug détaillé" _m23d_cr "$_m23d_e02_c" \
    '[.spec.config.exporters | to_entries[] | select((.key | startswith("debug")) and (.value.verbosity // "basic") == "detailed")] | length == 0'
  check_cmd "$_m23d_e02_c : métriques internes exposées au pod (lecteur Prometheus, port 8888)" _m23d_cr "$_m23d_e02_c" \
    '[.spec.config.service.telemetry.metrics.readers[]?.pull.exporter.prometheus | select(.port == 8888 and .host != "localhost" and .host != "127.0.0.1")] | length >= 1'
done
check_cmd "otel-agent : k8sattributes dans le pipeline (métadonnées des pods émetteurs)" bash -c \
  'grep -q "^k8sattributes" <<<"$1"' _ "$(_m23d_processeurs otel-agent)"
check_cmd "Service otel-agent-collector : trafic gardé sur le nœud (internalTrafficPolicy: Local)" _m23d_kq \
  '.spec.internalTrafficPolicy == "Local"' -n "$_m23d_ns" service otel-agent-collector

# --- 3. L'entrée externe et les politiques -----------------------------------------------------------------
check_cmd "Service otlp-externe : LoadBalancer 10.10.41.63, externalTrafficPolicy Local" _m23d_kq \
  '.spec.type == "LoadBalancer" and .spec.externalTrafficPolicy == "Local" and ([.status.loadBalancer.ingress[]?.ip] | index("10.10.41.63") != null)' \
  -n "$_m23d_ns" service otlp-externe
check_port "adm01 → 10.10.41.63:4317 (OTLP gRPC) accepte les connexions" "$_m23d_lb" 4317
check_cmd "CiliumNetworkPolicy traces-agent et traces-passerelle présentes" _m23d_kq \
  '[.items[].metadata.name] | (index("traces-agent") != null) and (index("traces-passerelle") != null)' \
  -n "$_m23d_ns" ciliumnetworkpolicies.cilium.io
check_cmd "sortie des espaces applicatifs vers l'agent (CiliumClusterwideNetworkPolicy vers traces.otel-agent)" _m23d_kq \
  '[.items[] | select([.spec.egress[]?.toEndpoints[]?.matchLabels["app.kubernetes.io/instance"]] | index("traces.otel-agent") != null)] | length >= 1' \
  ciliumclusterwidenetworkpolicies.cilium.io

# --- 4. Des spans circulent -------------------------------------------------------------------------------
check_cmd "Prometheus collecte les métriques des Collectors (cibles up dans traces)" _m23d_prom_positif \
  'count(up{namespace="traces"} == 1)'
check_cmd "la passerelle a accepté des spans dans la dernière heure (otelcol_receiver_accepted_spans)" _m23d_prom_positif \
  'sum(increase({__name__=~"otelcol_receiver_accepted_spans(_total)?", namespace="traces", pod=~"otel-passerelle-.*"}[1h]))'
check_cmd "aucune span refusée par les récepteurs sur 1 h (otelcol_receiver_refused_spans)" _m23d_prom_nul \
  'sum(increase({__name__=~"otelcol_receiver_refused_spans(_total)?", namespace="traces"}[1h]))'

# --- 5. La documentation -----------------------------------------------------------------------------------
check_cmd "plateforme/medisphere : docs/observabilite/traces/architecture.md (agent, passerelle, 10.10.41.63)" \
  _m23d_contient plateforme/medisphere docs/observabilite/traces/architecture.md 'otel-agent' 'otel-passerelle' '10\.10\.41\.63'
