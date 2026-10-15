# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E16.sh — M15-E16 : Routage avancé : poids, en-têtes, réécritures, gRPC et TLS
# À lancer depuis adm01. Lecture seule (kube get, requêtes HTTPS et gRPC vers gw-par1, journal).

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E16 — Routage avancé : poids, en-têtes, réécritures, gRPC et TLS"
require_cmd kubectl jq curl

_m15o_r="$(_m15o_kjson httproute essai-avance -n wb-essais)"
_m15o_u="https://essai.$_M15O_APPS"
_m15o_journal_f="$_M15O_TRAVAIL/e16/journal.md"

# --- Route ---------------------------------------------------------------------------------------------
check_cmd "wb-essais/essai-avance acceptée par gw-par1" _m15o_jq "$_m15o_r" \
  'any(.status.parents[]?; .parentRef.name == "gw-par1" and any(.conditions[]?; .type == "Accepted" and .status == "True"))'
check_cmd "essai-avance : poids 90/10 (ou 9/1) entre agnhost-v1 et agnhost-v2" _m15o_jq "$_m15o_r" \
  'any(.spec.rules[]?; ([.backendRefs[]? | {(.name): (.weight // 1)}] | add // {}) as $w | $w["agnhost-v1"] != null and $w["agnhost-v2"] != null and ($w["agnhost-v1"] == 9 * $w["agnhost-v2"]))'
check_cmd "essai-avance : en-tête X-Canari, URLRewrite, RequestRedirect, RequestHeaderModifier" _m15o_jq "$_m15o_r" \
  '[.spec.rules[]?] as $r | any($r[]; any(.matches[]?.headers[]?; .name == "X-Canari")) and any($r[].filters[]?; .type == "URLRewrite") and any($r[].filters[]?; .type == "RequestRedirect") and any($r[].filters[]?; .type == "RequestHeaderModifier")'

# --- Comportement ----------------------------------------------------------------------------------------
_m15o_canari() {
  local i
  for i in 1 2 3 4 5; do
    curl -fsS --max-time "$WB_TIMEOUT" -H "X-Canari: oui" "$_m15o_u/hostname" 2>/dev/null || echo "echec$i"
    echo
  done | grep -vc '^agnhost-v2-' || true
}
check_output "avec X-Canari: oui, les 5 réponses viennent de la v2" '^0$' _m15o_canari
check_output "/v2/hostname est réécrit vers /hostname de la v2" '^agnhost-v2-' _m15o_corps "$_m15o_u/v2/hostname"
check_output "/ancien/hostname est redirigé (301) vers /hostname" "^301 ${_m15o_u}/hostname\$" \
  curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time "$WB_TIMEOUT" "$_m15o_u/ancien/hostname"
check_output "l'en-tête X-Medisphere-Env: essai est ajouté (et imposé)" '^essai$' \
  _m15o_corps "$_m15o_u/header?key=X-Medisphere-Env" -H 'X-Medisphere-Env: prod'
_m15o_v2="$(for _ in $(seq 40); do curl -fsS --max-time "$WB_TIMEOUT" "$_m15o_u/hostname" 2>/dev/null; echo; done | grep -c '^agnhost-v2-' || true)"
check_cmd "sans en-tête, la v2 reçoit une minorité du trafic (${_m15o_v2:-0}/40, attendu ≈ 4)" \
  bash -c '(( $1 >= 1 && $1 <= 12 ))' _ "${_m15o_v2:-0}"

# --- gRPC -------------------------------------------------------------------------------------------------
_m15o_g="$(_m15o_kjson grpcroute essai-grpc -n wb-essais)"
check_cmd "wb-essais/essai-grpc (GRPCRoute) acceptée par gw-par1" _m15o_jq "$_m15o_g" \
  'any(.status.parents[]?; .parentRef.name == "gw-par1" and any(.conditions[]?; .type == "Accepted" and .status == "True"))'
if command -v grpcurl >/dev/null 2>&1; then
  _m15o_p="$(cd "$(dirname "${BASH_SOURCE[0]}")/../ressources" && pwd)"
  check_output "grpc.health.v1.Health/Check répond SERVING à travers gw-par1" '"status": *"SERVING"' \
    grpcurl -max-time "$WB_TIMEOUT" -import-path "$_m15o_p" -proto E16-health.proto \
      -servername "grpc-essai.$_M15O_APPS" -authority "grpc-essai.$_M15O_APPS" -d '{}' "$_M15O_GW:443" grpc.health.v1.Health/Check
else
  skip "grpc.health.v1.Health/Check répond SERVING" "grpcurl absent de ce poste"
fi

# --- TLS de bout en bout et référence croisée (essais nettoyés à l'étape 7 : preuves dans le journal) ---
check_output "CRD tlsroutes : seule la version v1 est servie (canal standard v1.6)" '^v1$' \
  _m15o_versions_servies tlsroutes.gateway.networking.k8s.io
check_cmd "journal : certificat du backend tls-essai montré par openssl (et non le joker)" \
  grep -qE 'CN *= *tls-essai\.apps\.par1\.medisphere\.internal' "$_m15o_journal_f"
check_cmd "journal : refus RefNotPermitted constaté avant le ReferenceGrant" grep -q 'RefNotPermitted' "$_m15o_journal_f"
check_output "nettoyage : gw-essai-tls et wb-essais-2 supprimées" '^0$' \
  bash -c 'jq -r "[.items[]? | select(.metadata.name == \"gw-essai-tls\")] | length" <<<"$1"; ' _ "$(_m15o_kjson gateways -n wb-essais)"
check_cmd "nettoyage : l'espace wb-essais-2 n'existe plus" _m15o_jq "$(_m15o_kjson namespaces)" \
  '[.items[]? | select(.metadata.name == "wb-essais-2")] | length == 0'
