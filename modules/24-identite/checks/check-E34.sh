# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E34.sh — M24-E34 : Ouvrir un nouveau service au SSO en temps limité
# À lancer depuis adm01, à la fin de l'épreuve. Lecture seule : client oauth2-proxy (wb-checks), requête
# anonyme sur slo.apps… (redirections suivies jusqu'à la page de connexion), HTTPRoutes et CNP (kube),
# journal sur main de plateforme/medisphere.

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"

title "M24-E34 — Ouvrir un nouveau service au SSO en temps limité"
require_cmd jq curl kubectl

_m24p_e34_hote=slo.apps.par1.medisphere.internal
_m24p_e34_client="$(_m24d_kc_client oauth2-proxy)"
check_cmd "Client oauth2-proxy : redirection exacte https://$_m24p_e34_hote/oauth2/callback" _m24d_json "$_m24p_e34_client" \
  '(.redirectUris // []) | index("https://slo.apps.par1.medisphere.internal/oauth2/callback") != null'
check_cmd "Client oauth2-proxy : aucune redirection avec joker" _m24d_json "$_m24p_e34_client" \
  'all((.redirectUris // [])[]; contains("*") | not)'
check_cmd "plateforme/identite : la redirection de Pyrra est dans le code (main)" \
  _m24d_contient "$(_m24p_tofu_tout)" 'https://slo\.apps\.par1\.medisphere\.internal/oauth2/callback'

# Requête anonyme : on suit les redirections (OAuth2 Proxy → Keycloak) et on regarde où l'on arrive.
_m24p_e34_fin="$(curl -s -L --max-redirs 4 --max-time "$WB_TIMEOUT" --cacert "$_M24D_RACINE" -o /dev/null \
  -w '%{url_effective}' "https://$_m24p_e34_hote/" 2>/dev/null || true)"
check_cmd "Requête anonyme sur https://$_m24p_e34_hote/ : renvoyée vers la connexion du royaume medisphere" \
  _m24d_contient "$_m24p_e34_fin" '^https://sso\.par1\.medisphere\.internal/realms/medisphere/protocol/openid-connect/auth\?.*client_id=oauth2-proxy'

_m24p_e34_routes="$(kube get httproutes.gateway.networking.k8s.io -A -o json 2>/dev/null \
  | jq -c --arg h "$_m24p_e34_hote" '[.items[] | select((.spec.hostnames // []) | index($h) != null)]' 2>/dev/null || true)"
check_cmd "Une seule HTTPRoute pour $_m24p_e34_hote, dans l'espace oauth2-proxy" _m24d_json "$_m24p_e34_routes" \
  'length == 1 and .[0].metadata.namespace == "oauth2-proxy"'
check_cmd "Cette HTTPRoute ne vise plus directement pyrra-api" _m24d_json "$_m24p_e34_routes" \
  'all(.[].spec.rules[]?.backendRefs[]?; .name != "pyrra-api")'
check_cmd "CNP pyrra-api-entree : la Gateway (entité ingress) n'atteint plus Pyrra directement" _m24d_json \
  "$(kube -n supervision get ciliumnetworkpolicies.cilium.io pyrra-api-entree -o json 2>/dev/null || true)" \
  '([.spec.ingress[]?.fromEntities[]?] | index("ingress") == null)
   and any(.spec.ingress[]?.fromEndpoints[]?; .matchLabels["io.kubernetes.pod.namespace"] == "oauth2-proxy")'

_m24p_e34_journal="$(_m24p_arbre plateforme/medisphere docs/socle/journal | grep -Ei 'M24-E34' | head -n 1 || true)"
_m24p_e34_jc=""
[[ -n "$_m24p_e34_journal" ]] && _m24p_e34_jc="$(_m24p_doc "$_m24p_e34_journal")"
check_cmd "Journal de l'épreuve sur main (docs/socle/journal/…M24-E34…)" test -n "$_m24p_e34_jc"
check_cmd "Journal : heures, preuve du refus (403) pour un groupe non autorisé, durée totale" _m24p_tous "$_m24p_e34_jc" \
  '[0-2][0-9]:[0-5][0-9]' '403' 'dur[ée]e|min'
