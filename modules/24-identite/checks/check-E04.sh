# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E04.sh — M24-E04 : Installer Keycloak sur idp01 et le publier
# À lancer depuis adm01. Lecture seule : DNS, NetBox, TLS (racine MédiSphère), découverte OIDC du
# royaume master, interface de gestion de idp01 (santé), SSH en consultation sur idp01 (fichiers,
# unités, ports, requête SELECT dans la base de Keycloak par le compte postgres).

# shellcheck source=_m24-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-decouverte.sh"

title "M24-E04 — Installer Keycloak sur idp01 et le publier"
require_cmd jq curl dig openssl

_m24d_e04_fqdn="idp01.$_M24D_DOMAINE"

# _m24d_e04_sql REQUÊTE — SELECT en lecture dans la base keycloak (sortie brute, vide si erreur).
_m24d_e04_sql() {
  _m24d_ssh "$_M24D_IDP" "cd /tmp && sudo -n -u postgres psql -d keycloak -XtAc \"$1\""
}

# _m24d_e04_aucun REGEX TEXTE — aucune ligne du texte ne correspond.
_m24d_e04_aucun() { ! grep -Eq -- "$1" <<<"$2"; }

# --- 1. La machine et le service -------------------------------------------------------------------
check_cmd "NetBox : VM idp01 déclarée (étiquettes socle et role-idp)" _m24d_json \
  "$(netbox_api "virtualization/virtual-machines/?name=idp01" 2>/dev/null || true)" \
  '.count == 1 and ([.results[0].tags[].slug] | index("socle") != null and index("role-idp") != null)'
check_dns "A idp01.par1.medisphere.internal → 10.10.20.30" "$_m24d_e04_fqdn" A '^10\.10\.20\.30$'
check_dns "sso.par1.medisphere.internal → VIP des répartiteurs 10.10.70.200" "sso.$_M24D_DOMAINE" A '^10\.10\.70\.200$'
check_ssh_output "idp01 : Keycloak 26.7 ou ultérieur installé dans /opt/keycloak-<version>, lien /opt/keycloak" "$_M24D_IDP" \
  '^/opt/keycloak-26\.([7-9]|[1-9][0-9])\.[0-9]+$' "readlink -f /opt/keycloak"
check_ssh_output "idp01 : Java 25 (OpenJDK de Debian 13)" "$_M24D_IDP" 'version "25' "java -version 2>&1 | head -n 1"
check_ssh "idp01 : unité keycloak.service active, sous l'utilisateur keycloak" "$_M24D_IDP" \
  "systemctl is-active --quiet keycloak.service && [ \"\$(systemctl show -p User --value keycloak.service)\" = keycloak ]"
check_ssh "idp01 : démarrage optimisé (kc.sh start --optimized), jamais start-dev" "$_M24D_IDP" \
  "systemctl show -p ExecStart --value keycloak.service | grep -q 'start --optimized' && ! systemctl show -p ExecStart --value keycloak.service | grep -q start-dev"
check_ssh_output "idp01 : keycloak.conf lisible par root et le groupe keycloak seulement (mot de passe de la base)" "$_M24D_IDP" \
  '^640 root keycloak$' "stat -c '%a %U %G' /opt/keycloak/conf/keycloak.conf"
check_ssh_output "idp01 : port 8080 (HTTP) fermé ; 8443 et 9000 ouverts" "$_M24D_IDP" '^8443 9000$' \
  "ss -Hltn | awk '{print \$4}' | sed 's/.*://' | grep -Ex '8080|8443|9000' | sort -un | paste -sd' '"
check_ssh_output "idp01 : PostgreSQL n'écoute que sur la boucle locale" "$_M24D_IDP" '^local$' \
  "if ss -Hltn 'sport = :5432' | awk '{print \$4}' | grep -Evq '^(127\\.0\\.0\\.1|\\[::1\\]):5432\$'; then echo exposé; else echo local; fi"
check_ssh "idp01 : renouvellement automatique du certificat (cert-renewer@keycloak.timer actif)" "$_M24D_IDP" \
  "systemctl is-active --quiet cert-renewer@keycloak.timer"

# --- 2. TLS et santé -------------------------------------------------------------------------------
check_cmd "idp01:8443 : certificat ACME vérifié jusqu'à la racine MédiSphère, nom idp01" _m24d_chaine_tls "$_m24d_e04_fqdn" 8443
check_http "idp01:9000 /health/ready : Keycloak prêt (interface de gestion, HTTPS)" \
  "https://$_m24d_e04_fqdn:9000/health/ready" 200 --cacert "$_M24D_RACINE"
check_output "idp01:9000 /metrics : métriques exposées (metrics-enabled)" '^(# HELP|# TYPE|[a-z_]+\{)' \
  curl -sf --max-time "$WB_TIMEOUT" --cacert "$_M24D_RACINE" "https://$_m24d_e04_fqdn:9000/metrics"
check_cmd "sso.par1.medisphere.internal:443 : certificat des répartiteurs vérifié (nom sso)" \
  _m24d_chaine_tls "sso.$_M24D_DOMAINE" 443
check_cmd "Découverte du royaume master : émetteur https://sso.par1.medisphere.internal/realms/master (option hostname)" \
  _m24d_json "$(_m24d_public /realms/master/.well-known/openid-configuration)" \
  '.issuer == "https://sso.par1.medisphere.internal/realms/master"
   and (.authorization_endpoint | startswith("https://sso.par1.medisphere.internal/"))'
check_http "Console d'administration joignable depuis MGMT par sso (HTTP 200)" \
  "$_M24D_SSO/admin/master/console/" 200 --cacert "$_M24D_RACINE"
check_output "HAProxy : le contrôle de santé de be_sso vise /health/ready sur le port 9000 (configuration de lb01)" \
  'health/ready' _m24d_ssh lb01 "sudo -n grep -A12 'backend be_sso' /etc/haproxy/haproxy.cfg"

# --- 3. Les comptes du royaume master ----------------------------------------------------------------
# Lecture directe de la base (SELECT) : le royaume master n'est pas lisible par le compte des checks.
_m24d_e04_admins="$(_m24d_e04_sql "SELECT u.username || ':' || u.enabled FROM user_entity u JOIN realm r ON r.id = u.realm_id WHERE r.name = 'master' AND u.service_account_client_link IS NULL ORDER BY 1")"
if [[ -z "$_m24d_e04_admins" ]]; then
  _ko "Base keycloak illisible depuis idp01 (sudo -n -u postgres psql -d keycloak) : comptes de master non contrôlés"
else
  check_output "master : compte de bris de glace kc-secours présent et actif" '^kc-secours:true$' printf '%s\n' "$_m24d_e04_admins"
  if [[ -n "$_M24D_MOI" ]]; then
    check_output "master : ton compte nominatif $_M24D_MOI-admin présent et actif" "^${_M24D_MOI//./\\.}-admin:true\$" printf '%s\n' "$_m24d_e04_admins"
    check_output "master : $_M24D_MOI-admin a un second facteur OTP enregistré" '^1$' _m24d_e04_sql \
      "SELECT count(*) FROM credential c JOIN user_entity u ON u.id = c.user_id JOIN realm r ON r.id = u.realm_id WHERE r.name = 'master' AND u.username = '$_M24D_MOI-admin' AND c.type = 'otp'"
  else
    skip "Ton compte $_M24D_MOI-admin dans master" "WB_MOI non renseigné dans lab/lab.env"
  fi
  check_cmd "master : plus aucun administrateur temporaire (temp-admin, tmp-admin, admin)" \
    _m24d_e04_aucun '^(temp-admin|tmp-admin|admin):' "$_m24d_e04_admins"
  check_output "master : kc-secours et ton compte ont le rôle admin" '^2$' _m24d_e04_sql \
    "SELECT count(DISTINCT u.username) FROM user_role_mapping m JOIN keycloak_role k ON k.id = m.role_id JOIN user_entity u ON u.id = m.user_id JOIN realm r ON r.id = u.realm_id WHERE r.name = 'master' AND k.name = 'admin' AND k.client_role = false AND u.username IN ('kc-secours', '${_M24D_MOI:-?}-admin')"
fi
