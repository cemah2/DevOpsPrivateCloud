# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E27.sh — M24-E27 : Durcir Keycloak : sessions, jetons, force brute, administration
# À lancer depuis adm01. Lecture seule : royaume medisphere et ses clients (wb-checks), code OpenTofu
# sur main, royaume master par SELECT sur idp01, keycloak.conf d'idp01 (sudo -n), master.md sur main.

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"

title "M24-E27 — Durcir Keycloak : sessions, jetons, force brute, administration"
require_cmd jq curl

_m24p_e27_r="$(_m24p_royaume)"
if [[ -z "$_m24p_e27_r" ]]; then
  _ko "API d'administration du royaume medisphere illisible avec wb-checks"
else
  check_cmd "medisphere : rotation des jetons de rafraîchissement (révocation, réutilisation 0)" _m24d_json "$_m24p_e27_r" \
    '.revokeRefreshToken == true and .refreshTokenMaxReuse == 0'
  check_cmd "medisphere : détection de force brute TEMPORAIRE, au plus 5 échecs" _m24d_json "$_m24p_e27_r" \
    '.bruteForceProtected == true and .permanentLockout == false and .failureFactor >= 1 and .failureFactor <= 5'
  check_cmd "medisphere : politique de mot de passe d'au moins 12 caractères" _m24d_json "$_m24p_e27_r" \
    '(.passwordPolicy // "") | test("length\\(([1-9][2-9]|[2-9][0-9]|[0-9]{3,})\\)")'
  check_cmd "medisphere : jeton d'accès 300 s, session inactive 1800 s, maximale 36000 s" _m24d_json "$_m24p_e27_r" \
    '.accessTokenLifespan == 300 and .ssoSessionIdleTimeout == 1800 and .ssoSessionMaxLifespan == 36000'
  check_cmd "medisphere : événements et événements d'administration actifs" _m24d_json "$_m24p_e27_r" \
    '.eventsEnabled == true and .adminEventsEnabled == true'
fi
_m24p_e27_code="$(_m24d_contenu_main plateforme/identite tofu/royaume.tf)"
check_cmd "tofu/royaume.tf : durées écrites, rotation, force brute et en-têtes décrits dans le code" _m24p_tous "$_m24p_e27_code" \
  'access_token_lifespan' 'sso_session_idle_timeout' 'sso_session_max_lifespan' 'revoke_refresh_token' \
  'brute_force_detection' 'headers' 'strict_transport_security'

_m24p_e27_c="$(_m24p_clients_metier)"
if [[ -z "$_m24p_e27_c" || "$_m24p_e27_c" == "[]" ]]; then
  _ko "Clients du royaume medisphere illisibles avec wb-checks"
else
  check_cmd "Clients : aucun flux implicite" _m24d_json "$_m24p_e27_c" 'all(.[]; .implicitFlowEnabled != true)'
  check_cmd "Clients : aucun Direct Access Grants" _m24d_json "$_m24p_e27_c" 'all(.[]; .directAccessGrantsEnabled != true)'
  check_cmd "Clients : aucune redirection avec joker (*)" _m24d_json "$_m24p_e27_c" \
    'all(.[]; all((.redirectUris // [])[]; contains("*") | not))'
  check_cmd "Clients publics : PKCE S256 exigé" _m24d_json "$_m24p_e27_c" \
    'all(.[] | select(.publicClient == true and .standardFlowEnabled == true); .attributes["pkce.code.challenge.method"] == "S256")'
fi

# --- master (hors du code) ---------------------------------------------------------------------------
check_output "master : détection de force brute active" '^true$' \
  _m24p_sql "SELECT ra.value FROM realm_attribute ra JOIN realm r ON r.id = ra.realm_id WHERE r.name = 'master' AND ra.name = 'bruteForceProtected'"
check_output "master : verrouillage temporaire seulement (pas permanent)" '^false$' \
  _m24p_sql "SELECT ra.value FROM realm_attribute ra JOIN realm r ON r.id = ra.realm_id WHERE r.name = 'master' AND ra.name = 'permanentLockout'"
check_output "master : politique de mot de passe avec une longueur minimale" 'length\(' \
  _m24p_sql "SELECT password_policy FROM realm WHERE name = 'master'"
check_cmd "docs/securite/identite/master.md sur main (réglages faits à la main, datés)" \
  _m24p_tous "$(_m24p_doc "$_M24P_DOC/master.md")" 'force brute|brute force' 'mot de passe|password'
check_ssh_output "idp01 : fonction impersonation désactivée (features-disabled)" "$_M24D_IDP" 'impersonation' \
  "sudo -n grep -E '^features-disabled=' /opt/keycloak/conf/keycloak.conf"
