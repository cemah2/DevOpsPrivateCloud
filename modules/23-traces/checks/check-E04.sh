# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et TraceQL entre apostrophes
#
# check-E04.sh — M23-E04 : Instrumenter MédiAgenda avec le SDK Python
# Lecture seule : dépôts GitLab (mediagenda/api, mediagenda/deploiement, plateforme/medisphere) en GET,
# Deployments de mediagenda-dev et mediagenda-recette (kube), recherches TraceQL dans Tempo.

# shellcheck source=_m23-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-decouverte.sh"

title "M23-E04 — Instrumenter MédiAgenda avec le SDK Python"
require_cmd jq kubectl curl

# --- 1. Le code et la livraison -------------------------------------------------------------------------
check_cmd "mediagenda/api (main) : SDK et instrumentations déclarés (pyproject.toml)" _m23d_contient mediagenda/api pyproject.toml \
  'opentelemetry-sdk' 'opentelemetry-instrumentation-fastapi' 'opentelemetry-instrumentation-psycopg' 'opentelemetry-instrumentation-redis'
check_cmd "mediagenda/api (main) : uv.lock à jour (opentelemetry-sdk 1.45)" _m23d_contient mediagenda/api uv.lock \
  'name = "opentelemetry-sdk"'
check_cmd "mediagenda/deploiement (main) : component telemetrie (variables OTEL_* standard, agent du nœud)" \
  _m23d_contient mediagenda/deploiement components/telemetrie/kustomization.yaml 'OTEL_SERVICE_NAME' 'mediagenda-api' \
  'OTEL_EXPORTER_OTLP_ENDPOINT' 'otel-agent-collector\.traces'
for _m23d_e04_env in dev recette; do
  check_cmd "mediagenda/deploiement : overlay $_m23d_e04_env inclut le component telemetrie" \
    _m23d_contient mediagenda/deploiement "overlays/$_m23d_e04_env/kustomization.yaml" 'components/telemetrie'
  check_cmd "mediagenda-$_m23d_e04_env : conteneur api avec OTEL_SERVICE_NAME=mediagenda-api et OTEL_RESOURCE_ATTRIBUTES" _m23d_kq \
    '[.spec.template.spec.containers[] | select(.name == "api") | .env[]? | select((.name == "OTEL_SERVICE_NAME" and .value == "mediagenda-api") or .name == "OTEL_RESOURCE_ATTRIBUTES")] | length == 2' \
    -n "mediagenda-$_m23d_e04_env" deployment mediagenda
done

# --- 2. Les traces --------------------------------------------------------------------------------------
for _m23d_e04_env in dev recette; do
  check_cmd "traces récentes (1 h) de mediagenda-api en $_m23d_e04_env (deployment.environment.name)" _m23d_traces 3600 \
    "{ resource.service.name = \"mediagenda-api\" && resource.deployment.environment.name = \"$_m23d_e04_env\" }"
done
check_cmd "spans PostgreSQL (psycopg) dans les traces de l'API (24 h)" _m23d_traces 86400 \
  '{ resource.service.name = "mediagenda-api" && (span.db.system.name = "postgresql" || span.db.system = "postgresql") }'
check_cmd "spans Valkey (redis) dans les traces de l'API (24 h)" _m23d_traces 86400 \
  '{ resource.service.name = "mediagenda-api" && (span.db.system.name = "redis" || span.db.system = "redis") }'
check_cmd "span métier mediagenda.rendez_vous.creer, fille de la span serveur (24 h)" _m23d_traces 86400 \
  '{ resource.service.name = "mediagenda-api" && kind = server } > { name = "mediagenda.rendez_vous.creer" }'
check_cmd "métadonnées Kubernetes ajoutées par l'agent (k8s.namespace.name, 1 h)" _m23d_traces 3600 \
  '{ resource.service.name = "mediagenda-api" && resource.k8s.namespace.name =~ "mediagenda-.+" }'
check_cmd "aucune sonde tracée (/sante, /pret, /metrics) sur 1 h" _m23d_sans_traces 3600 \
  '{ resource.service.name = "mediagenda-api" && (span.url.path =~ "/(sante|pret|metrics)" || span.http.target =~ "/(sante|pret|metrics).*") }'
check_cmd "aucun attribut patient (nom, motif) sur 24 h" _m23d_sans_traces 86400 \
  '{ resource.service.name = "mediagenda-api" && (span.mediagenda.patient != nil || span.mediagenda.motif != nil || span.patient != nil) }'

# --- 3. La documentation ------------------------------------------------------------------------------------
check_cmd "plateforme/medisphere : conventions-telemetrie.md (service.name, interdits)" \
  _m23d_contient plateforme/medisphere docs/observabilite/traces/conventions-telemetrie.md 'service\.name' 'mediagenda-api' 'interdit'
