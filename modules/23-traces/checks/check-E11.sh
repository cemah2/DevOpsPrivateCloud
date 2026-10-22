# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E11.sh — M23-E11 : Revue : la configuration du Collector du stagiaire
# Lecture seule : compte rendu de revue dans plateforme/medisphere (GitLab, GET) ; objets de l'espace traces
# (kube) : la proposition de Lucas n'a pas été appliquée.

# shellcheck source=_m23-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-operationnel.sh"

title "M23-E11 — Revue : la configuration du Collector du stagiaire"
require_cmd jq kubectl curl

_M23O_E11="$(_m23d_fichier plateforme/medisphere docs/observabilite/traces/revue-collector-lucas.md 2>/dev/null || true)"
_m23o_e11_lignes="$(grep -Ec '^\|[[:space:]]*[0-9]+[[:space:]]*\|' <<<"$_M23O_E11" || true)"
check_cmd "plateforme/medisphere : docs/observabilite/traces/revue-collector-lucas.md présent" test -n "$_M23O_E11"
check_cmd "au moins 10 constats numérotés dans le tableau de revue (${_m23o_e11_lignes:-0})" test "${_m23o_e11_lignes:-0}" -ge 10
for _m23o_e11_m in 'memory_limiter' 'loadbalancing|traceID' 'otlp_grpc' 'debug' 'TLS|chiffr' 'RBAC|ClusterRole' 'InfoG[ée]r|tiers|souverainet'; do
  check_cmd "la revue traite : $_m23o_e11_m" grep -Eqi -- "$_m23o_e11_m" <<<"$_M23O_E11"
done
check_cmd "la proposition n'est pas appliquée (pas de Service otel-lucas dans traces)" _m23d_kq \
  '[.items[].metadata.name] | index("otel-lucas") == null' -n "$_m23d_ns" services
check_cmd "aucun Collector en image « latest » ou hors de Harbor" _m23d_kq \
  '[.items[] | select((.spec.image // "") | (test(":latest$") or (test("^registry\\.par1\\.medisphere\\.internal/") | not)))] | length == 0' \
  -n "$_m23d_ns" opentelemetrycollectors.opentelemetry.io
