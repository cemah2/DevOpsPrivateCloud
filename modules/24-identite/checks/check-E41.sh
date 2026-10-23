# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E41.sh — M24-E41 « Panne : boucle de redirection derrière OAuth2 Proxy »
# Vérifie, en lecture seule depuis adm01 :
#   - client Keycloak oauth2-proxy : l'URI de retour exacte de mon01 est enregistrée, aucune joker, et
#     le point d'autorisation l'accepte (code HTTP, aucune connexion faite) ;
#   - instance de mon01 : active, une visite sans session est renvoyée vers Keycloak avec SA propre URI
#     de retour, et le cookie posé respecte le préfixe __Host- (Secure, Path=/, sans Domain) ;
#   - fichier de configuration de l'instance sans cookie_domains ;
#   - RB-246 : section OAuth2 Proxy.

# shellcheck source=_m24-expert-b.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert-b.sh"

title "M24-E41 — Panne : boucle de redirection derrière OAuth2 Proxy"
require_cmd jq curl

_m24y_e41_rappel="$_M24Y_O2P_URL/oauth2/callback"

# --- 1. Client Keycloak --------------------------------------------------------------------------------
_m24y_e41_c="$(_m24c_kc_client oauth2-proxy)"
if [[ -z "$_m24y_e41_c" ]]; then
  _ko "client oauth2-proxy illisible ou absent (wb-checks, lab/bin/check 24 18)"
else
  check_cmd "oauth2-proxy : l'URI de retour exacte de mon01 est enregistrée" \
    _m24c_json "$_m24y_e41_c" '.redirectUris | index($u) != null' --arg u "$_m24y_e41_rappel"
  check_cmd "oauth2-proxy : aucune URI de retour à joker" \
    _m24c_json "$_m24y_e41_c" '[.redirectUris[] | select(test("\\*"))] | length == 0'
fi
check_output "Keycloak accepte cette URI de retour (formulaire de connexion, pas d'erreur)" '^200$' \
  _m24y_code_auth oauth2-proxy "$_m24y_e41_rappel"

# --- 2. Instance de mon01 ------------------------------------------------------------------------------
check_ssh "mon01 : unité oauth2-proxy-mailpit active" "$_M24C_MON01" 'systemctl is-active --quiet oauth2-proxy-mailpit'
_m24y_e41_h="$(_m24y_entetes "$_M24Y_O2P_URL/")"
_m24y_e41_loc="$(sed -n 's/^[Ll]ocation: //p' <<<"$_m24y_e41_h" | head -n 1)"
check_cmd "visite sans session : renvoi vers le point d'autorisation du royaume medisphere" \
  bash -c '[[ "$1" == "$2/protocol/openid-connect/auth?"* ]]' _ "$_m24y_e41_loc" "$_M24D_EMETTEUR"
check_cmd "le renvoi porte l'URI de retour de mon01 (pas celle d'une autre instance)" \
  bash -c 'grep -qF "redirect_uri=$(jq -rn --arg v "$2" "\$v|@uri")&" <<<"$1&"' _ "$_m24y_e41_loc" "$_m24y_e41_rappel"
_m24y_e41_cookie="$(grep -i '^set-cookie: __Host-' <<<"$_m24y_e41_h" | head -n 1 || true)"
check_cmd "cookie __Host- : Secure, Path=/ et SANS attribut Domain (sinon le navigateur le rejette)" \
  bash -c '[[ -n "$1" ]] && grep -qi "; *secure" <<<"$1" && grep -qi "; *path=/\(;\|$\)" <<<"$1" && ! grep -qi "; *domain=" <<<"$1"' \
  _ "$_m24y_e41_cookie"
check_cmd "mon01 : configuration de l'instance sans cookie_domains ni redirect_url étrangère" _m24y_ssh_ok "$_M24C_MON01" \
  'f=/etc/oauth2-proxy/mailpit/oauth2-proxy.cfg; sudo -n test -f $f && ! sudo -n grep -Eq "^[[:space:]]*cookie_domains" $f \
   && sudo -n grep -Eq "^[[:space:]]*redirect_url[[:space:]]*=[[:space:]]*\"https://mon01\.par1\.medisphere\.internal:8443/oauth2/callback\"" $f && echo oui'

# --- 3. Runbook ---------------------------------------------------------------------------------------------
check_output "RB-246 : section OAuth2 Proxy (boucle, cookie, URI de retour)" '^#+ .*(OAuth2 Proxy|mandataire)' _m24y_rb246
