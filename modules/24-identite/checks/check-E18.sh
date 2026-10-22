# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E18.sh — M24-E18 : OAuth2 Proxy devant Hubble, Pyroscope et Mailpit.
# Vérifie, en lecture seule depuis adm01 :
#   - le client Keycloak oauth2-proxy (confidentiel, flux standard seul, PKCE S256, trois URI exactes) ;
#   - les deux releases de l'espace oauth2-proxy (version, réplicas, groupes autorisés, PKCE, portées),
#     l'Application Argo CD, l'absence de route directe vers hubble-ui ;
#   - qu'une visite sans session des trois interfaces est renvoyée vers le royaume medisphere ;
#   - sur mon01 : l'unité oauth2-proxy-mailpit active, l'API de Mailpit toujours lisible par wb-checks.

# shellcheck source=_m24-operationnel-c.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-operationnel-c.sh"

title "M24-E18 — OAuth2 Proxy devant Hubble, Pyroscope et Mailpit"
require_cmd jq curl kubectl

_m24c_e18_hubble="https://hubble.apps.$_M24C_DOMAINE"
_m24c_e18_pyroscope="https://pyroscope.apps.$_M24C_DOMAINE"
_m24c_e18_mailpit="https://mon01.$_M24C_DOMAINE:8443"

# --- 1. Le client Keycloak -------------------------------------------------------------------------
_m24c_e18_client="$(_m24c_kc_client oauth2-proxy)"
check_cmd "Client oauth2-proxy : confidentiel, flux standard seul (ni implicite, ni mot de passe, ni compte de service)" \
  _m24c_json "$_m24c_e18_client" \
  '.enabled and (.publicClient | not) and .standardFlowEnabled and (.implicitFlowEnabled | not)
   and (.directAccessGrantsEnabled | not) and (.serviceAccountsEnabled | not)'
check_cmd "Client oauth2-proxy : PKCE S256 exigé" _m24c_json "$_m24c_e18_client" \
  '.attributes["pkce.code.challenge.method"] == "S256"'
check_cmd "Client oauth2-proxy : exactement les trois URI de retour, sans joker" _m24c_json "$_m24c_e18_client" \
  '(.redirectUris | sort) == ($a | sort)' \
  --argjson a "[\"$_m24c_e18_hubble/oauth2/callback\",\"$_m24c_e18_pyroscope/oauth2/callback\",\"$_m24c_e18_mailpit/oauth2/callback\"]"

# --- 2. Les releases du cluster -------------------------------------------------------------------
_m24c_e18_deps="$(_m24c_k -n oauth2-proxy get deployments -o json)"
for _m24c_e18_r in oauth2-proxy-hubble oauth2-proxy-pyroscope; do
  check_cmd "$_m24c_e18_r : déployée, deux réplicas disponibles, image ≥ v7.15.5" _m24c_json "$_m24c_e18_deps" \
    '[.items[] | select(.metadata.name == $n)][0]
     | (.status.availableReplicas // 0) >= 2
       and (.spec.template.spec.containers[0].image
            | capture(":v(?<v>[0-9]+\\.[0-9]+\\.[0-9]+)") .v | split(".") | map(tonumber)
            | (.[0] > 7) or (.[0] == 7 and (.[1] > 15 or (.[1] == 15 and .[2] >= 5))))' \
    --arg n "$_m24c_e18_r"
done

# _m24c_e18_cfg RELEASE — fichier oauth2_proxy.cfg rendu par le chart (ConfigMap du même nom).
_m24c_e18_cfg() { _m24c_k -n oauth2-proxy get configmap "$1" -o json | jq -r '.data["oauth2_proxy.cfg"] // empty' 2>/dev/null || true; }
_m24c_e18_cfg_hubble="$(_m24c_e18_cfg oauth2-proxy-hubble)"
_m24c_e18_cfg_pyro="$(_m24c_e18_cfg oauth2-proxy-pyroscope)"
check_cmd "oauth2-proxy-hubble : fournisseur keycloak-oidc, PKCE S256, groupes plateforme-admins, plateforme, support SEULEMENT" \
  bash -c 'grep -Eq "^provider *= *\"keycloak-oidc\"" <<<"$1" && grep -Eq "^code_challenge_method *= *\"S256\"" <<<"$1" \
    && grep -Eq "^allowed_groups" <<<"$1" && ! grep -E "^allowed_groups" <<<"$1" | grep -Eq "mediagenda|medidoc|direction|securite"' \
  _ "$_m24c_e18_cfg_hubble"
check_cmd "oauth2-proxy-pyroscope : groupes de développement autorisés (mediagenda, medidoc), PKCE S256" \
  bash -c 'grep -Eq "^code_challenge_method *= *\"S256\"" <<<"$1" && grep -E "^allowed_groups" <<<"$1" | grep -q mediagenda \
    && grep -E "^allowed_groups" <<<"$1" | grep -q medidoc' _ "$_m24c_e18_cfg_pyro"
check_cmd "Les deux releases ne demandent pas la portée « groups » (inconnue du royaume : invalid_scope)" \
  bash -c '! grep -Eq "^scope *=.*\bgroups\b" <<<"$1$2" && grep -Eq "^scope *=" <<<"$1" && grep -Eq "^scope *=" <<<"$2"' \
  _ "$_m24c_e18_cfg_hubble" "$_m24c_e18_cfg_pyro"
check_cmd "Cookies de session __Host-, sécurisés" \
  bash -c 'for c in "$1" "$2"; do grep -Eq "^cookie_secure *= *true" <<<"$c" || exit 1; done; [[ "$3" == *__Host-* && "$4" == *__Host-* ]]' _ \
  "$_m24c_e18_cfg_hubble" "$_m24c_e18_cfg_pyro" \
  "$(jq -r '[.items[] | select(.metadata.name == "oauth2-proxy-hubble") | .spec.template.spec.containers[0].args[]?] | join(" ")' <<<"$_m24c_e18_deps" 2>/dev/null || true)" \
  "$(jq -r '[.items[] | select(.metadata.name == "oauth2-proxy-pyroscope") | .spec.template.spec.containers[0].args[]?] | join(" ")' <<<"$_m24c_e18_deps" 2>/dev/null || true)"
check_cmd "Application Argo CD oauth2-proxy : synchronisée et saine" _m24c_json \
  "$(_m24c_k -n argocd get applications.argoproj.io oauth2-proxy -o json)" \
  '.status.sync.status == "Synced" and .status.health.status == "Healthy"'

# --- 3. Plus de chemin direct vers hubble-ui ----------------------------------------------------------
_m24c_e18_routes="$(_m24c_k get httproutes.gateway.networking.k8s.io -A -o json)"
check_cmd "Aucune HTTPRoute ne mène directement au Service hubble-ui (seulement par OAuth2 Proxy)" _m24c_json "$_m24c_e18_routes" \
  '(.items | length > 0) and ([.items[].spec.rules[]?.backendRefs[]? | select(.name == "hubble-ui")] | length == 0)'
check_cmd "La politique d'entrée de hubble-ui n'accepte plus l'Envoy de la Gateway" _m24c_json \
  "$(_m24c_k -n kube-system get ciliumnetworkpolicies.cilium.io hubble-ui-entree -o json)" \
  '([.spec.ingress[]?.fromEntities[]?] | index("ingress")) == null and ([.spec.ingress[]?.fromEndpoints[]?] | length > 0)'

# --- 4. Ce que voit un visiteur sans session -----------------------------------------------------------
check_cmd "$_m24c_e18_hubble : sans session, renvoi vers Keycloak (client oauth2-proxy, PKCE)" \
  _m24c_vers_sso "$_m24c_e18_hubble/" oauth2-proxy
check_cmd "$_m24c_e18_pyroscope : sans session, renvoi vers Keycloak (client oauth2-proxy, PKCE)" \
  _m24c_vers_sso "$_m24c_e18_pyroscope/" oauth2-proxy
check_cmd "$_m24c_e18_mailpit : sans session, renvoi vers Keycloak (client oauth2-proxy, PKCE)" \
  _m24c_vers_sso "$_m24c_e18_mailpit/" oauth2-proxy

# --- 5. mon01 ------------------------------------------------------------------------------------------
check_ssh "mon01 : oauth2-proxy-mailpit.service actif" "$_M24C_MON01" \
  "systemctl is-active --quiet oauth2-proxy-mailpit.service"
_m24c_e18_api_mailpit() { mailpit_api "messages?limit=1" 2>/dev/null | jq -e '.total >= 0' >/dev/null 2>&1; }
check_cmd "mon01 : l'API de Mailpit répond toujours au compte des vérifications (8025)" _m24c_e18_api_mailpit
