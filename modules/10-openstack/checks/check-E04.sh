# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées sur l'hôte distant ou par bash -c
#
# check-E04.sh — M10-E04 : Déployer OpenStack
# À lancer depuis adm01. Lecture seule : état des nœuds en SSH (ip, docker ps, keepalived.conf
# généré, lus avec sudo -n), certificat présenté par la VIP externe, CLI openstack (token issue,
# list), copie de travail ~/src/openstack, fichiers de ~/.config/openstack, API GitLab en GET.

# shellcheck source=_m10-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-decouverte.sh"

title "M10-E04 — Déployer OpenStack"
require_cmd jq curl openssl openstack

_m10d_e04_racine="$(_m10d_racine)"

# --- 1. Points d'accès ---------------------------------------------------------------------------
check_ssh_output "osctl01 : VIP 10.10.50.200 et 10.10.50.201 sur ens18" osctl01 '^2$' \
  'ip -o -4 addr show dev ens18 | grep -cE "inet 10\.10\.50\.(200|201)/"'
check_ssh "osctl01 : keepalived généré par Kolla avec le VRID 150" osctl01 \
  'sudo -n grep -Eq "virtual_router_id[[:space:]]+150([^0-9]|$)" /etc/kolla/keepalived/keepalived.conf'
check_port "VIP interne : Keystone joignable (10.10.50.200:5000)" 10.10.50.200 5000
check_http "API publique : https://$_M10D_NOM_EXT:5000/v3 répond (TLS vérifié, racine MédiSphère seule)" \
  "https://$_M10D_NOM_EXT:5000/v3" 200 --cacert "$_m10d_e04_racine" --noproxy '*'
check_cmd "VIP externe : chaîne de la PKI MédiSphère, valable pour $_M10D_NOM_EXT" \
  _m10d_chaine_ok "$_M10D_NOM_EXT" 5000
check_output "VIP externe : certificat émis par « MédiSphère Intermediate CA »" 'Interm(é|e)diate CA' \
  bash -c 'timeout 5 openssl s_client -connect "$1:5000" -servername "$1" </dev/null 2>/dev/null | openssl x509 -noout -issuer -nameopt utf8' _ "$_M10D_NOM_EXT"

# --- 2. L'API, vue de adm01 ---------------------------------------------------------------------
check_cmd "CLI : jeton obtenu avec le cloud $_M10D_CLOUD" _m10d_os_ok token issue
_m10d_e04_ep="$(_m10d_os endpoint list --interface public)"
check_cmd "Catalogue : tous les points d'accès publics en https://$_M10D_NOM_EXT" \
  _m10d_jq "$_m10d_e04_ep" "length >= 5 and all(.[]; .URL | startswith(\"https://$_M10D_NOM_EXT\"))"
_m10d_e04_cs="$(_m10d_os compute service list --service nova-compute)"
check_cmd "Nova : nova-compute activé et « up » sur oscmp01 et oscmp02" _m10d_jq "$_m10d_e04_cs" \
  '[.[] | select(.Status == "enabled" and .State == "up") | .Host] | (index("oscmp01") != null and index("oscmp02") != null)'
_m10d_e04_ag="$(_m10d_os network agent list)"
check_cmd "OVN : passerelle (« OVN Controller Gateway agent ») vivante sur osctl01" _m10d_jq "$_m10d_e04_ag" \
  'map(select(.Host == "osctl01" and (."Agent Type" | test("Gateway")) and .Alive == true)) | length >= 1'
check_cmd "OVN : contrôleurs vivants sur oscmp01 et oscmp02" _m10d_jq "$_m10d_e04_ag" \
  '[.[] | select((."Agent Type" | test("^OVN Controller agent$")) and .Alive == true) | .Host] | (index("oscmp01") != null and index("oscmp02") != null)'
check_cmd "OVN : aucun agent mort" _m10d_jq "$_m10d_e04_ag" 'length >= 3 and all(.[]; .Alive == true)'

# --- 3. Les conteneurs -------------------------------------------------------------------------
for _m10d_e04_h in osctl01 oscmp01 oscmp02; do
  check_ssh_output "$_m10d_e04_h : conteneurs Kolla en service, aucun « unhealthy »" "$_m10d_e04_h" '^ok$' \
    'n=$(sudo -n docker ps -q | wc -l); m=$(sudo -n docker ps -q --filter health=unhealthy | wc -l); [ "$n" -ge 5 ] && [ "$m" -eq 0 ] && echo ok'
  check_ssh "$_m10d_e04_h : images debian de la série 2026.1 seulement" "$_m10d_e04_h" \
    'i=$(sudo -n docker ps --format "{{.Image}}"); [ -n "$i" ] && ! grep -v ":2026\.1-debian-" <<<"$i" | grep -q .'
done
check_ssh "osctl01 : conteneurs keystone, nova_api, neutron_server, ovn_northd, haproxy en service" osctl01 \
  'for c in keystone nova_api neutron_server ovn_northd haproxy; do sudo -n docker ps --format "{{.Names}}" | grep -qx "$c" || exit 1; done'

# --- 4. Secrets et clients ---------------------------------------------------------------------
check_cmd "Dépôt : haproxy.pem chiffré sous l'identité « critique »" \
  _m10d_vault_critique "$_M10D_OS/etc/kolla/certificates/haproxy.pem"
check_cmd "plateforme/openstack (main) : haproxy.pem versionné" \
  _m10d_fichier_main plateforme/openstack etc/kolla/certificates/haproxy.pem
check_cmd "Dépôt : TLS externe activé dans globals.yml" \
  grep -Eq '^kolla_enable_tls_external:[[:space:]]*"?(yes|true)"?' "$_M10D_OS/etc/kolla/globals.yml"
check_cmd "Copie de travail : aucune clé privée en clair (hors .venv, collections, .git)" \
  bash -c '[[ -d "$1/etc/kolla" ]] && ! grep -rlIE -- "-----BEGIN (EC |RSA )?PRIVATE KEY-----" "$1" --exclude-dir=.venv --exclude-dir=collections --exclude-dir=.git 2>/dev/null | grep -q .' _ "$_M10D_OS"
check_ssh "osctl01 : aucune clé privée en clair hors des emplacements de Kolla (/tmp, /home, /root)" osctl01 \
  '! sudo -n grep -rlIE -- "-----BEGIN (EC |RSA )?PRIVATE KEY-----" /tmp /var/tmp /home /root 2>/dev/null | grep -q .'
check_cmd "adm01 : secure.yaml en 600" _m10d_mode "$HOME/.config/openstack/secure.yaml" 600
check_cmd "adm01 : clouds.yaml sans mot de passe" \
  bash -c '[[ -s "$1" ]] && ! grep -Eiq "^[[:space:]]*password[[:space:]]*:" "$1"' _ "$HOME/.config/openstack/clouds.yaml"
