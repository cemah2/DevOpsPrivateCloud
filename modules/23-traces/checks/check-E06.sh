# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et TraceQL entre apostrophes
#
# check-E06.sh — M23-E06 : Instrumenter MédiDoc avec le SDK Go
# Lecture seule : dépôts GitLab (medidoc/medidoc, medidoc/deploiement, mediagenda/api) en GET, Deployments
# (kube), recherches TraceQL dans Tempo.

# shellcheck source=_m23-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-operationnel.sh"

title "M23-E06 — Instrumenter MédiDoc avec le SDK Go"
require_cmd jq kubectl curl

# --- 1. Le code ----------------------------------------------------------------------------------------
check_cmd "medidoc/medidoc (main) : go.mod avec otel 1.47, otelhttp, otelaws, autoprop" _m23d_contient medidoc/medidoc go.mod \
  'go\.opentelemetry\.io/otel v1\.47\.' 'otelhttp v0\.7[0-9]\.' 'otelaws v0\.7[0-9]\.' 'propagators/autoprop'
check_cmd "medidoc/medidoc (main) : gestionnaire HTTP enveloppé par otelhttp (cmd/medidoc/main.go)" \
  _m23d_contient medidoc/medidoc cmd/medidoc/main.go 'otelhttp\.NewHandler'
check_cmd "mediagenda/api (main) : appel de MédiDoc instrumenté (httpx + instrumentation httpx)" _m23d_contient mediagenda/api pyproject.toml \
  'opentelemetry-instrumentation-httpx' '"httpx'
check_cmd "medidoc/deploiement (main) : component telemetrie (OTEL_SERVICE_NAME=medidoc)" \
  _m23d_contient medidoc/deploiement components/telemetrie/kustomization.yaml 'OTEL_SERVICE_NAME' 'medidoc' 'otel-agent-collector\.traces'

# --- 2. Le déploiement ---------------------------------------------------------------------------------
check_output "medidoc-dev : OTEL_SERVICE_NAME=medidoc sur le conteneur medidoc" '^medidoc$' \
  _m23o_env_deploy medidoc-dev medidoc medidoc OTEL_SERVICE_NAME
_m23o_e06_url_medidoc() {
  kube get -n mediagenda-dev configmaps -o json 2>/dev/null | jq -r '.items[].data.MEDIAGENDA_MEDIDOC_URL // empty' 2>/dev/null || true
}
check_output "mediagenda-dev : MEDIAGENDA_MEDIDOC_URL vers MédiDoc de dev (ConfigMap de paramètres)" \
  'medidoc\.medidoc-dev(\.svc(\.cluster\.local)?)?' _m23o_e06_url_medidoc

# --- 3. Une trace, deux services ----------------------------------------------------------------------
check_cmd "traces de MédiDoc (service.name=medidoc) sur 24 h" _m23d_traces 86400 '{ resource.service.name = "medidoc" }'
check_cmd "spans S3 (instrumentation AWS) sous les requêtes de MédiDoc (24 h)" _m23d_traces 86400 \
  '{ resource.service.name = "medidoc" && kind = server } >> { resource.service.name = "medidoc" && kind = client && name =~ "S3\\..*" }'
check_cmd "UNE trace traverse MédiAgenda puis MédiDoc (propagation W3C, 24 h)" _m23d_traces 86400 \
  '{ resource.service.name = "mediagenda-api" } >> { resource.service.name = "medidoc" && kind = server }'
check_cmd "aucune sonde de MédiDoc tracée (/healthz, /readyz, /metrics) sur 1 h" _m23d_sans_traces 3600 \
  '{ resource.service.name = "medidoc" && span.url.path =~ "/(healthz|readyz|metrics)" }'
