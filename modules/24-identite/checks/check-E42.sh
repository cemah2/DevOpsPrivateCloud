# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes et filtres entre apostrophes
#
# check-E42.sh — M24-E42 « Panne : le fournisseur d'identité ne répond plus comme avant »
# Vérifie, en lecture seule depuis adm01 :
#   - la découverte publique répond, avec l'émetteur public et des points de terminaison sous lui ;
#   - idp01 : hostname de keycloak.conf, certificat de Keycloak émis par la PKI MédiSphère au nom
#     d'idp01 et valable, PostgreSQL avec assez de connexions et aucun refus récent dans le journal ;
#   - lb01 et lb02 : contrôle de santé de be_sso sur l'interface de gestion (9000) ;
#   - RB-246 : section sur le fournisseur.

# shellcheck source=_m24-expert-b.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert-b.sh"

title "M24-E42 — Panne : le fournisseur d'identité ne répond plus comme avant"
require_cmd jq curl

# --- 1. Ce que voient les clients ----------------------------------------------------------------------
_m24y_e42_d="$(_m24d_public /realms/medisphere/.well-known/openid-configuration)"
check_cmd "découverte publique : émetteur $_M24D_EMETTEUR" _m24c_json "$_m24y_e42_d" '.issuer == $e' --arg e "$_M24D_EMETTEUR"
check_cmd "découverte publique : points d'autorisation et de jetons sous l'émetteur public" \
  _m24c_json "$_m24y_e42_d" '(.authorization_endpoint | startswith($e + "/")) and (.token_endpoint | startswith($e + "/"))' \
  --arg e "$_M24D_EMETTEUR"

# --- 2. idp01 ---------------------------------------------------------------------------------------------
check_ssh_output "idp01 : keycloak.conf, hostname = l'URL publique sans port" "$_M24D_IDP" \
  '^hostname=https://sso\.par1\.medisphere\.internal/?$' "sudo -n grep -E '^hostname=' $_M24Y_KC_CONF"
check_cmd "idp01 : certificat de Keycloak au nom d'idp01, chaîné à la racine MédiSphère, valable au moins 1 h" \
  _m24y_ssh_ok "$_M24D_IDP" \
  'c=/etc/keycloak/tls/keycloak.crt; r=/usr/local/share/ca-certificates/medisphere-root-ca.crt;
   sudo -n openssl verify -CAfile $r -untrusted $c $c >/dev/null 2>&1 && sudo -n openssl x509 -in $c -noout -checkend 3600 >/dev/null \
   && sudo -n openssl x509 -in $c -noout -ext subjectAltName 2>/dev/null | grep -q "DNS:idp01\.par1\.medisphere\.internal" && echo oui'
check_output "idp01 : PostgreSQL accepte au moins 50 connexions (max_connections)" '^([5-9][0-9]|[1-9][0-9]{2,})$' \
  _m24p_sql "SHOW max_connections"
check_cmd "idp01 : aucun refus de connexion de PostgreSQL dans le journal de Keycloak depuis 15 min" _m24y_ssh_ok "$_M24D_IDP" \
  '! sudo -n journalctl -u keycloak --since "-15min" --no-pager -o cat 2>/dev/null | grep -Eqi "too many clients|remaining connection slots|too many connections" && echo oui'

# --- 3. Répartiteurs -------------------------------------------------------------------------------------
for _m24y_e42_lb in "${_M24Y_LB[@]}"; do
  check_cmd "$_m24y_e42_lb : be_sso contrôlé sur l'interface de gestion (check port 9000, check-ssl)" _m24y_ssh_ok "$_m24y_e42_lb" \
    "sudo -n grep -E '^[[:space:]]*server idp0[0-9][[:space:]]' $_M24Y_HAPROXY | grep -q 'check port 9000 check-ssl' \
     && ! sudo -n grep -E '^[[:space:]]*server idp0[0-9][[:space:]]' $_M24Y_HAPROXY | grep -Eq 'check port (8443|80|443)\b' && echo oui"
done

# --- 4. Runbook ---------------------------------------------------------------------------------------------
check_output "RB-246 : section sur le fournisseur (émetteur, certificat, répartiteurs, base)" \
  '^#+ .*[Ff]ournisseur' _m24y_rb246
