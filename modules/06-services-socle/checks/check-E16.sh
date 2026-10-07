# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E16.sh — M06-E16 : Kea DHCPv4 remplace dnsmasq
# À lancer depuis adm01, sbx66 (2066) démarrée. Lecture seule.

# shellcheck source=_m06-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-operationnel.sh"

title "M06-E16 — Kea DHCPv4 remplace dnsmasq"
require_cmd jq curl

_m06o_pvehote="${WB_PVE_HOST:-pve01}"
# Configuration chargée par kea-dhcp4 (socket de contrôle UNIX), en JSON.
_m06o_conf="$(remote dns01 'printf "{ \"command\": \"config-get\" }" | sudo -n socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket' 2>/dev/null || true)"

check_ssh "dns01 : dnsmasq n'est plus installé" dns01 \
  '! dpkg-query -W -f="\${Status}" dnsmasq 2>/dev/null | grep -q "install ok installed"'
check_ssh "dns01 : isc-kea-dhcp4-server actif et activé" dns01 \
  'systemctl is-active --quiet isc-kea-dhcp4-server && systemctl is-enabled --quiet isc-kea-dhcp4-server'
check_ssh "dns01 : Kea 3.0 (dépôt ISC)" dns01 \
  'dpkg-query -W -f="\${Version}" isc-kea-dhcp4 | grep -q "^3\.0\."'
check_ssh "dns01 : kea-dhcp4 écoute UDP 67" dns01 \
  'sudo -n ss -Hlunp "sport = :67" | grep -q kea-dhcp4'
check_cmd "configuration chargée : sous-réseau 10.10.99.0/24 d'identifiant 99" \
  jq -e '.arguments.Dhcp4.subnet4 | map(select(.id == 99 and .subnet == "10.10.99.0/24")) | length == 1' <<<"$_m06o_conf"
check_cmd "configuration chargée : plage 10.10.99.100 - 10.10.99.199" \
  jq -e '[.arguments.Dhcp4.subnet4[] | select(.id == 99) | .pools[].pool | gsub(" "; "")] | index("10.10.99.100-10.10.99.199") != null' <<<"$_m06o_conf"
check_cmd "configuration chargée : routeur 10.10.99.1 et DNS 10.10.20.10" \
  jq -e '(.arguments.Dhcp4 | [.["option-data"][], (.subnet4[] | select(.id == 99) | .["option-data"][])]
          | (map(select(.name == "routers" and (.data | test("10\\.10\\.99\\.1\\b")))) | length > 0)
            and (map(select(.name == "domain-name-servers" and (.data | test("10\\.10\\.20\\.10")))) | length > 0))' <<<"$_m06o_conf"
check_cmd "configuration chargée : bail de 12 h, baux en memfile persistant" \
  jq -e '.arguments.Dhcp4 | .["valid-lifetime"] == 43200 and .["lease-database"].type == "memfile" and .["lease-database"].persist == true' <<<"$_m06o_conf"
check_ssh "dns01 : configuration valide pour kea-dhcp4 -t" dns01 \
  'sudo -n kea-dhcp4 -t /etc/kea/kea-dhcp4.conf >/dev/null 2>&1'

# --- La VM de test ---------------------------------------------------------------------------------------
if remote "$_m06o_pvehote" 'qm status 2066 | grep -q running' >/dev/null 2>&1; then
  _m06o_ip="$(remote "$_m06o_pvehote" 'qm guest cmd 2066 network-get-interfaces' 2>/dev/null \
    | jq -r '[.[] | select(.name != "lo") | .["ip-addresses"][]? | select(.["ip-address-type"] == "ipv4") | .["ip-address"]][0] // empty' || true)"
  check_output "sbx66 : adresse dans 10.10.99.100-199 (${_m06o_ip:-aucune})" '^10\.10\.99\.1[0-9][0-9]$' echo "$_m06o_ip"
  check_ssh "dns01 : le bail de sbx66 est dans le fichier de baux de Kea (/var/lib/kea)" dns01 \
    "sudo -n grep -q '^${_m06o_ip:-0.0.0.0},' /var/lib/kea/*leases4*.csv*"
else
  skip "bail de sbx66" "VM 2066 arrêtée ou absente : démarre-la pour vérifier le service rendu"
fi

check_cmd "plateforme/ansible : scénario Molecule du rôle kea_dhcp4 sur main" \
  _m06o_fichier_main "$_M06O_PROJET_ANSIBLE" molecule/kea_dhcp4/molecule.yml
# Absent de main, et la forge répond (sinon « absent » ne prouverait rien).
_m06o_dnsmasq_retire() {
  _m06o_fichier_main "$_M06O_PROJET_ANSIBLE" ansible.cfg \
    && ! _m06o_fichier_main "$_M06O_PROJET_ANSIBLE" roles/dnsmasq/tasks/main.yml
}
check_cmd "plateforme/ansible : rôle dnsmasq retiré de main" _m06o_dnsmasq_retire
