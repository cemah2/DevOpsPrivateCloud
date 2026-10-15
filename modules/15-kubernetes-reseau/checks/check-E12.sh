# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E12.sh — M15-E12 : La Gateway principale gw-par1 et le TLS
# À lancer depuis adm01. Lecture seule (kube get, curl/openssl vers 10.10.41.10, dig, GitLab).

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E12 — La Gateway principale gw-par1 et le TLS"
require_cmd kubectl jq curl openssl dig

_m15o_gwj="$(_m15o_kjson gateway gw-par1 -n passerelles)"
_m15o_nsj="$(_m15o_kjson namespaces)"
_m15o_rt="$(_m15o_kjson httproute mediagenda -n mediagenda-recette)"
_m15o_redir="$(_m15o_kjson httproute redirection-https -n passerelles)"

# --- Espaces ------------------------------------------------------------------------------------------
for _m15o_e in passerelles mediagenda-recette wb-essais; do
  check_cmd "espace $_m15o_e étiqueté medisphere.internal/exposition=oui" _m15o_jq "$_m15o_nsj" --arg e "$_m15o_e" \
    'any(.items[]?; .metadata.name == $e and .metadata.labels["medisphere.internal/exposition"] == "oui")'
done
check_cmd "espace mediagenda-dev NON étiqueté pour l'exposition" _m15o_jq "$_m15o_nsj" \
  'any(.items[]?; .metadata.name == "mediagenda-dev" and (.metadata.labels["medisphere.internal/exposition"] // "") != "oui")'

# --- Gateway ------------------------------------------------------------------------------------------
check_cmd "gw-par1 : classe cilium, adresse demandée 10.10.41.10" _m15o_jq "$_m15o_gwj" \
  '.spec.gatewayClassName == "cilium" and any(.spec.addresses[]?; .value == "10.10.41.10")'
check_output "gw-par1 : Programmed" '^True$' _m15o_condition "$_m15o_gwj" Programmed
check_cmd "gw-par1 : adresse attribuée 10.10.41.10" _m15o_jq "$_m15o_gwj" 'any(.status.addresses[]?; .value == "10.10.41.10")'
check_cmd "écouteur http : port 80, HTTP" _m15o_jq "$_m15o_gwj" 'any(.spec.listeners[]?; .name == "http" and .port == 80 and .protocol == "HTTP")'
check_cmd "écouteur https : 443, *.apps.par1.medisphere.internal, terminaison TLS avec le Secret apps-joker" \
  _m15o_jq "$_m15o_gwj" 'any(.spec.listeners[]?; .name == "https" and .port == 443 and .protocol == "HTTPS" and .hostname == "*.apps.par1.medisphere.internal" and (.tls.mode // "Terminate") == "Terminate" and any(.tls.certificateRefs[]?; .name == "apps-joker" and ((.namespace // "passerelles") == "passerelles")))'
check_cmd "routes admises par étiquette d'espace medisphere.internal/exposition=oui sur les deux écouteurs" \
  _m15o_jq "$_m15o_gwj" '[.spec.listeners[]? | select(.name == "http" or .name == "https") | .allowedRoutes.namespaces | select(.from == "Selector" and .selector.matchLabels["medisphere.internal/exposition"] == "oui")] | length == 2'
check_cmd "écouteur https : références résolues (certificat lu)" _m15o_jq "$_m15o_gwj" \
  'any(.status.listeners[]?; .name == "https" and any(.conditions[]?; .type == "ResolvedRefs" and .status == "True"))'

# --- Routes -----------------------------------------------------------------------------------------------
check_cmd "redirection-https : attachée au seul écouteur http, filtre RequestRedirect vers https" \
  _m15o_jq "$_m15o_redir" '([.spec.parentRefs[]? | .sectionName] == ["http"]) and any(.spec.rules[]?.filters[]?; .type == "RequestRedirect" and .requestRedirect.scheme == "https")'
check_cmd "mediagenda-recette/mediagenda : acceptée par gw-par1 (écouteur https) et références résolues" \
  _m15o_jq "$_m15o_rt" 'any(.status.parents[]?; .parentRef.name == "gw-par1" and any(.conditions[]?; .type == "Accepted" and .status == "True") and any(.conditions[]?; .type == "ResolvedRefs" and .status == "True"))'
_m15o_refus="$(_m15o_kjson httproute -n mediagenda-dev)"
check_cmd "aucune route de mediagenda-dev n'est acceptée par gw-par1" _m15o_jq "$_m15o_refus" \
  '[.items[]?.status.parents[]? | select(.parentRef.name == "gw-par1") | .conditions[]? | select(.type == "Accepted" and .status == "True")] | length == 0'

# --- Comportement --------------------------------------------------------------------------------------
_m15o_r443="$(_m15o_resolve "$_M15O_NOM_MA" 443 "$_M15O_GW")"
_m15o_r80="$(_m15o_resolve "$_M15O_NOM_MA" 80 "$_M15O_GW")"
check_output "https://$_M15O_NOM_MA/sante répond 200 par 10.10.41.10 (certificat vérifié)" '^200$' \
  _m15o_code "https://$_M15O_NOM_MA/sante" "$_m15o_r443"
check_output "http://$_M15O_NOM_MA/sante répond 301 vers https" '^301 https://' \
  curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time "$WB_TIMEOUT" "$_m15o_r80" "http://$_M15O_NOM_MA/sante"
_m15o_c="$(_m15o_cert "$_M15O_GW" 443 "$_M15O_NOM_MA")"
check_cmd "certificat présenté : émis par la PKI MédiSphère, pour *.apps.par1.medisphere.internal" \
  _m15o_cert_pki_joker "$_m15o_c"

# --- NetBox / DNS ---------------------------------------------------------------------------------------
check_dns "gw-par1.par1.medisphere.internal résout en 10.10.41.10" gw-par1.par1.medisphere.internal A '^10\.10\.41\.10$'
check_output "10.10.41.10 a pour nom inverse gw-par1.par1.medisphere.internal" '^gw-par1\.par1\.medisphere\.internal\.$' \
  dig +short +time="$WB_TIMEOUT" -x 10.10.41.10
check_output "NetBox : 10.10.41.10 porte le nom gw-par1.par1.medisphere.internal" '^gw-par1\.par1\.medisphere\.internal$' \
  _m15o_nom_netbox 10.10.41.10

# --- Code et hygiène -------------------------------------------------------------------------------------
check_cmd "composants/passerelles/gw-par1.yaml sur main de plateforme/k8s" \
  _m15o_fichier_main "$_M15O_K8S" composants/passerelles/gw-par1.yaml
check_cmd "aucune clé privée du joker sur le disque de adm01 (~/m15/e12, ~/m15/e12/tmp)" \
  bash -c '! grep -rlsq -- "PRIVATE KEY" "$1"' _ "$_M15O_TRAVAIL/e12"
