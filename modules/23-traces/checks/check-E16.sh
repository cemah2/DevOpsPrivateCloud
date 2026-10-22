# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E16.sh — M23-E16 « Capacité, rétention et sécurité de la chaîne de traces ». Lecture seule :
# la seule requête envoyée au point d'entrée est un POST OTLP SANS jeton (ou avec un jeton faux), refusé avant
# tout traitement (aucune donnée n'est écrite).

# shellcheck source=_m23-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-production.sh"

title "M23-E16 — Capacité, rétention et sécurité de la chaîne de traces"
require_cmd kubectl jq yq curl openssl

_m23_e16_racine="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"

check_cmd "Service LoadBalancer 10.10.41.63 (espace traces) : ports 4317 et 4318, externalTrafficPolicy Local" \
  _m23p_kq '[.items[] | select(.spec.type == "LoadBalancer")
            | select(([.status.loadBalancer.ingress[]?.ip] | index("10.10.41.63")) != null or .spec.loadBalancerIP == "10.10.41.63"
                     or (.metadata.annotations["lbipam.cilium.io/ips"] // "" | test("10\\.10\\.41\\.63")))
            | select(.spec.externalTrafficPolicy == "Local")
            | select(([.spec.ports[].port] | index(4317)) != null and ([.spec.ports[].port] | index(4318)) != null)] | length == 1' \
  -n traces services
check_cmd "certificat cert-manager prêt pour otlp.apps.par1.medisphere.internal (espace traces)" \
  _m23p_kq '[.items[] | select((.spec.dnsNames // []) | index("otlp.apps.par1.medisphere.internal"))
            | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] | length >= 1' \
  -n traces certificates.cert-manager.io

_m23_e16_tls() {
  local s
  s="$(openssl s_client -connect "$_m23p_lb:$1" -servername "$_m23p_nom_otlp" -verify_hostname "$_m23p_nom_otlp" \
    -verify_return_error -CAfile "$_m23_e16_racine" </dev/null 2>&1)" || return 1
  grep -q 'Verify return code: 0 (ok)' <<<"$s"
}
if [[ -r "$_m23_e16_racine" ]]; then
  check_cmd "10.10.41.63:4318 (OTLP/HTTP) : TLS valide pour $_m23p_nom_otlp, signé par la racine MédiSphère" _m23_e16_tls 4318
  check_cmd "10.10.41.63:4317 (OTLP/gRPC) : TLS valide pour $_m23p_nom_otlp, signé par la racine MédiSphère" _m23_e16_tls 4317
else
  skip "TLS du point d'entrée" "racine MédiSphère illisible sur ce poste : $_m23_e16_racine (WB_RACINE_PKI)"
fi

_m23_e16_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" --cacert "$_m23_e16_racine" \
    --resolve "$_m23p_nom_otlp:4318:$_m23p_lb" -X POST -H 'Content-Type: application/json' "$@" \
    --data '{"resourceSpans":[]}' "https://$_m23p_nom_otlp:4318/v1/traces" 2>/dev/null || true
}
check_output "OTLP/HTTP sans jeton : refusé (401)" '^401$' _m23_e16_code
check_output "OTLP/HTTP avec un jeton inconnu : refusé (401)" '^401$' _m23_e16_code -K <(printf 'header = "Authorization: Bearer jeton-inconnu-du-check"\n')

check_cmd "passerelle : extension bearertokenauth déclarée et active" \
  _m23p_config_collector "$_m23p_passerelle" '([.extensions | keys[] | select(test("^bearertokenauth"))] | length >= 1)
     and ([.service.extensions[]? | select(test("^bearertokenauth"))] | length >= 1)'
check_cmd "passerelle : un récepteur OTLP avec TLS ET authentification (gRPC et HTTP)" \
  _m23p_config_collector "$_m23p_passerelle" '[.receivers[] | select(.protocols.grpc.tls.cert_file? and .protocols.grpc.auth.authenticator?
     and .protocols.http.tls.cert_file? and .protocols.http.auth.authenticator?)] | length >= 1'
check_cmd "passerelle : taille des messages bornée (max_recv_msg_size_mib, max_request_body_size)" \
  _m23p_config_collector "$_m23p_passerelle" '[.receivers[] | select(.protocols.grpc.max_recv_msg_size_mib? and .protocols.http.max_request_body_size?)] | length >= 1'
check_cmd "passerelle : memory_limiter en tête de chaque pipeline" \
  _m23p_config_collector "$_m23p_passerelle" 'all(.service.pipelines[]; (.processors[0] // "") | test("^memory_limiter"))'
check_cmd "passerelle : exportateur vers Tempo avec file d'attente et reprises explicites" \
  _m23p_config_collector "$_m23p_passerelle" '[.exporters[] | select((.endpoint? // "") | test("tempo"))
     | select(.sending_queue.queue_size? and .retry_on_failure.enabled? != false)] | length >= 1'
_m23_e16_pas_de_jeton_git() {
  [[ -n "$(_m23p_arbre plateforme/observabilite otel)" ]] || return 1 # dépôt lisible, sinon on ne conclut rien
  ! _m23p_depot_contient plateforme/observabilite otel '^[[:space:]]*(token|tokens)[[:space:]]*:[[:space:]]*[^[:space:]]'
}
check_cmd "plateforme/observabilite/otel : aucun jeton écrit en clair (filename seulement)" _m23_e16_pas_de_jeton_git

check_cmd "Tempo : rétention explicite de 14 jours (block_retention 336h ou 14d)" \
  _m23p_tempo_conf_jq '(.backend_worker.compaction.block_retention // "") | test("^(336h|14d)$")'
check_cmd "Tempo : limites d'ingestion explicites (rate_limit_bytes, burst_size_bytes, max_bytes_per_trace)" \
  _m23p_tempo_conf_jq '.overrides.defaults as $d | ($d.ingestion.rate_limit_bytes // 0) > 0 and ($d.ingestion.burst_size_bytes // 0) > 0
     and ($d.global.max_bytes_per_trace // 0) > 0'
check_cmd "CiliumNetworkPolicy de l'espace traces : passerelle, Tempo et Pyroscope couverts" \
  _m23p_kq '[.items[].spec.endpointSelector.matchLabels // {} | tostring] as $s
     | ($s | any(test("otel-passerelle"))) and ($s | any(test("tempo"))) and ($s | any(test("pyroscope")))' \
  -n traces ciliumnetworkpolicies.cilium.io
check_cmd "docs/observabilite/traces/capacite-securite.md : dimensionnement, rétention, jetons" \
  _m23p_doc docs/observabilite/traces capacite-securite 'r[ée]tention' '(Go|Gi|GB|To)' 'jeton' 'rotation'
