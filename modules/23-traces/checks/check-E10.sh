# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et TraceQL entre apostrophes
#
# check-E10.sh — M23-E10 : Les pipelines du Collector : processeurs et données sensibles
# Lecture seule : CR des Collectors (kube) ; recherches TraceQL dans Tempo sur la DERNIÈRE HEURE : aucune
# span de sonde, aucun attribut interdit. Il faut du trafic récent (ressources/E05-trafic/trafic.sh).

# shellcheck source=_m23-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-operationnel.sh"

title "M23-E10 — Les pipelines du Collector : processeurs et données sensibles"
require_cmd jq kubectl curl

# --- 1. La configuration (au moins un Collector de la chaîne porte chaque fonction) -------------------------
_m23o_e10_cfg="$( { kube get -n "$_m23d_ns" opentelemetrycollectors.opentelemetry.io otel-agent -o json 2>/dev/null || echo '{}'; } |
  jq -c '.spec.config // {}' 2>/dev/null || echo '{}')"
_m23o_e10_q() { jq -e "$1" >/dev/null 2>&1 <<<"$_m23o_e10_cfg"; }
check_cmd "otel-agent : memory_limiter toujours en premier" bash -c \
  '[[ "$(head -n 1 <<<"$1")" == memory_limiter* ]]' _ "$(_m23d_processeurs otel-agent)"
check_cmd "otel-agent : un processeur filter (ou OTTL) actif dans le pipeline traces" _m23o_e10_q \
  '[.service.pipelines.traces.processors[] | select(startswith("filter"))] | length >= 1'
check_cmd "otel-agent : une réécriture d'attributs actif (transform, attributes ou redaction)" _m23o_e10_q \
  '[.service.pipelines.traces.processors[] | select(startswith("transform") or startswith("attributes") or startswith("redaction"))] | length >= 1'
check_cmd "otel-agent : k8sattributes et resourcedetection dans le pipeline (enrichissement)" _m23o_e10_q \
  '([.service.pipelines.traces.processors[] | select(startswith("k8sattributes"))] | length >= 1) and ([.service.pipelines.traces.processors[] | select(startswith("resourcedetection"))] | length >= 1)'

# --- 2. Le résultat, dans Tempo, sur la dernière heure ------------------------------------------------------
_m23o_e10_activite="$(_m23d_traceql_nb '{ resource.service.name =~ "mediagenda-api|medidoc" }' 3600)"
if [[ "$_m23o_e10_activite" -le 0 ]]; then
  check_cmd "trafic récent des applications dans Tempo (1 h) : relance ressources/E05-trafic/trafic.sh" false
else
  check_cmd "aucune span de sonde (/sante, /pret, /metrics, /healthz, /readyz) sur 1 h" _m23d_sans_traces 3600 \
    '{ span.url.path =~ "/(sante|pret|metrics|healthz|readyz)" || span.http.target =~ "/(sante|pret|metrics|healthz|readyz).*" }'
  check_cmd "aucun paramètre d'URL conservé (url.query, « ? » dans url.full ou http.target) sur 1 h" _m23d_sans_traces 3600 \
    '{ span.url.query != nil || span.url.full =~ ".*[?].*" || span.http.target =~ ".*[?].*" }'
  check_cmd "aucun littéral SQL en clair (db.query.text, db.statement) sur 1 h" _m23d_sans_traces 3600 \
    "{ span.db.query.text =~ \".*'[^?'][^']*'.*\" || span.db.statement =~ \".*'[^?'][^']*'.*\" }"
  check_cmd "aucun en-tête HTTP capturé (Authorization, Cookie…) sur 1 h" _m23d_sans_traces 3600 \
    '{ span.http.request.header.authorization != nil || span.http.request.header.cookie != nil || span."http.response.header.set-cookie" != nil }'
  check_cmd "aucune donnée patient en attribut (patient, nir, email) sur 1 h" _m23d_sans_traces 3600 \
    '{ span.mediagenda.patient != nil || span.patient != nil || span.patient.nir != nil || span.user.email != nil }'
fi
check_cmd "plateforme/medisphere : conventions-telemetrie.md décrit le masquage du Collector" \
  _m23d_contient plateforme/medisphere docs/observabilite/traces/conventions-telemetrie.md 'masquage|redaction' 'url\.query'
