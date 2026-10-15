# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E18.sh — M15-E18 : Migrer les Ingress d'InfoGér vers la Gateway API
# À lancer depuis adm01. Lecture seule (fichiers de ~/m15/e18, kube get, requêtes HTTPS).

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E18 — Migrer les Ingress d'InfoGér vers la Gateway API"
require_cmd kubectl jq curl

_m15o_d="$_M15O_TRAVAIL/e18"
_m15o_routes="$(_m15o_kjson httproutes -n wb-essais)"
_m15o_grpc="$(_m15o_kjson grpcroutes -n wb-essais)"

# --- Travail hors ligne ------------------------------------------------------------------------------
check_cmd "ingress2gateway installé sur adm01" command -v ingress2gateway
check_cmd "m15/e18/sortie-brute.yaml : sortie de la conversion (HTTPRoute produites)" \
  grep -qs '^kind: HTTPRoute' "$_m15o_d/sortie-brute.yaml"
check_cmd "m15/e18/avertissements.txt : avertissements de l'outil conservés" \
  grep -qsi 'annotation' "$_m15o_d/avertissements.txt"
check_cmd "migration.md : tableau qui couvre les annotations clés des sept Ingress" \
  bash -c 'f="$1"; for a in app-root permanent-redirect rewrite-target limit-rps canary-weight auth-type whitelist-source-range configuration-snippet backend-protocol ssl-passthrough affinity auth-url; do grep -qs -- "$a" "$f" || exit 1; done' _ "$_m15o_d/migration.md"
check_cmd "migration.md : conclusion chiffrée (pourcentages ou nombres d'annotations)" \
  grep -qsE '[0-9]+ ?%|[0-9]+ annotations' "$_m15o_d/migration.md"

# --- Routes migrées ----------------------------------------------------------------------------------
_m15o_acc() { # NOM_D_HÔTE — une route (HTTP ou gRPC) de wb-essais pour ce nom, acceptée par gw-par1
  jq -e --arg h "$1" '[.items[]? | select((.spec.hostnames // []) | index($h))
     | select(any(.status.parents[]?; .parentRef.name == "gw-par1" and any(.conditions[]?; .type == "Accepted" and .status == "True")))] | length > 0' \
    <<<"$(jq -s '{items: (map(.items // []) | add)}' <<<"$_m15o_routes$_m15o_grpc")" >/dev/null 2>&1
}
_m15o_infoger="$(jq -rs '[.[].items[]?.spec.hostnames[]? | select(test("-infoger\\.apps\\.par1\\.medisphere\\.internal$"))] | unique | join(" ")' <<<"$_m15o_routes$_m15o_grpc" 2>/dev/null || true)"
check_cmd "route du portail acceptée (portail-infoger.$_M15O_APPS)" _m15o_acc "portail-infoger.$_M15O_APPS"
check_cmd "route de l'API rendez-vous acceptée (api-rdv-infoger.$_M15O_APPS)" _m15o_acc "api-rdv-infoger.$_M15O_APPS"
check_cmd "au moins trois applications d'InfoGér migrées (noms : ${_m15o_infoger:-aucun})" \
  bash -c '[[ $(wc -w <<<"$1") -ge 3 ]]' _ "$_m15o_infoger"

# --- Comportement ----------------------------------------------------------------------------------
check_output "portail : « / » redirige vers /accueil (302)" '^302 https://portail-infoger\.apps\.par1\.medisphere\.internal/accueil$' \
  curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time "$WB_TIMEOUT" "https://portail-infoger.$_M15O_APPS/"
check_output "api-rdv : le préfixe /rdv est retiré avant le backend (/rdv/hostname → nom du pod)" '^agnhost-v[12]-' \
  _m15o_corps "https://api-rdv-infoger.$_M15O_APPS/rdv/hostname"
check_output "api-rdv : l'en-tête X-Version-Rdv: v2 force la v2" '^agnhost-v2-' \
  _m15o_corps "https://api-rdv-infoger.$_M15O_APPS/rdv/hostname" -H 'X-Version-Rdv: v2'

# --- Pas d'ingress-nginx --------------------------------------------------------------------------------
check_cmd "aucun contrôleur ingress-nginx sur k8s-par1" _m15o_jq "$(_m15o_kjson pods -A)" \
  '[.items[]? | select(any(.spec.containers[]?; .image | test("ingress-nginx/controller")))] | length == 0'
check_cmd "aucune IngressClass nginx sur k8s-par1" _m15o_jq "$(_m15o_kjson ingressclasses)" \
  '[.items[]? | select(.spec.controller == "k8s.io/ingress-nginx")] | length == 0'
