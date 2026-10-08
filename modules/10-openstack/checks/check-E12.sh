# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E12.sh — M10-E12 : Le réseau externe intégré au lab
# À lancer depuis adm01, e12-vm démarrée avec son IP flottante. Lecture seule ; SSH dans e12-vm (debian).

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E12 — Le réseau externe intégré au lab"
require_cmd openstack jq curl ssh

# --- Matrice des flux ---------------------------------------------------------------------------------
_m10o_m="$(_m10o_matrice)"
check_cmd "matrice des flux (main) : règles commentées propres au VLAN 52 (ref M10-E12)" \
  bash -c 'grep -q "ens19.52" <<<"$1" && grep -q "M10-E12" <<<"$1"' _ "$_m10o_m"
_m10o_generique() {
  # La règle générique « vers Internet » ne doit plus partir de LAB_IFS (qui contient ens19.52).
  [[ -n "$1" ]] && ! grep -Eq 'entree:[[:space:]]*\$LAB_IFS[[:space:]]*,.*sortie:[[:space:]]*\$WAN' <<<"$1"
}
check_cmd "matrice des flux (main) : la sortie générique vers Internet ne part plus de LAB_IFS" _m10o_generique "$_m10o_m"

# --- Configuration Neutron ----------------------------------------------------------------------------
_m10o_ml2="$(_m10o_conf_noeud "$_M10O_CTL" /etc/kolla/neutron-server/ml2_conf.ini)"
_m10o_nc="$(_m10o_conf_noeud "$_M10O_CTL" /etc/kolla/neutron-server/neutron.conf)"
check_cmd "neutron-server (généré) : path_mtu réglé" _m10o_ini_vaut "$_m10o_ml2" path_mtu '[0-9]+'
check_cmd "neutron-server (généré) : physical_network_mtus protège physnet1 à 1500" \
  _m10o_ini_vaut "$_m10o_ml2" physical_network_mtus '.*physnet1:1500.*'
check_cmd "neutron-server (généré) : global_physnet_mtu réglé" _m10o_ini_vaut "$_m10o_nc" global_physnet_mtu '[0-9]+'

_m10o_mtu_ok() {
  local id n=0 vus=0 net
  for id in $(_m10o_os network list -f value -c ID || true); do
    vus=$((vus + 1))
    net="$(_m10o_os network show -f json "$id" || true)"
    jq -e '.mtu == 1500' <<<"$net" >/dev/null 2>&1 || { echo "MTU différente de 1500 : $(jq -r '.name' <<<"$net") ($(jq -r '.mtu' <<<"$net"))"; n=$((n + 1)); }
  done
  # Au moins ext-net et un réseau de projet, sinon la liste n'a pas été lue.
  [[ "$vus" -ge 2 && "$n" -eq 0 ]]
}
check_cmd "tous les réseaux (projets et ext-net) ont une MTU de 1500" _m10o_mtu_ok

# --- e12-vm -------------------------------------------------------------------------------------------
_m10o_vm="$(_m10o_serveur e12-vm)"
_m10o_fip="$(_m10o_ip_flottante "$_m10o_vm")"
if [[ -n "$_m10o_fip" ]]; then
  check_ping "e12-vm : répond au ping sur $_m10o_fip depuis adm01" "$_m10o_fip"
  check_port "e12-vm : SSH joignable sur $_m10o_fip" "$_m10o_fip" 22
  check_cmd "e12-vm : dépôts Debian joignables en HTTP" \
    _m10o_ssh_instance "$_m10o_fip" 'curl -s -o /dev/null -m 10 -w "%{http_code}" http://deb.debian.org/debian/dists/ | grep -Eq "^(200|301|302)$"'
  check_cmd "e12-vm : dépôts Debian joignables en HTTPS" \
    _m10o_ssh_instance "$_m10o_fip" 'curl -s -o /dev/null -m 10 -w "%{http_code}" https://deb.debian.org/debian/dists/ | grep -Eq "^(200|301|302)$"'
  check_cmd "e12-vm : résolution DNS fonctionnelle" _m10o_ssh_instance "$_m10o_fip" 'getent hosts deb.debian.org >/dev/null'
  check_cmd "e12-vm : git01:443 injoignable" \
    _m10o_ssh_instance "$_m10o_fip" '! timeout 5 bash -c "</dev/tcp/10.10.20.12/443" 2>/dev/null'
  check_cmd "e12-vm : port 25 d'Internet injoignable" \
    _m10o_ssh_instance "$_m10o_fip" '! timeout 5 bash -c "</dev/tcp/1.1.1.1/25" 2>/dev/null'
else
  _ko "e12-vm : introuvable, ou sans IP flottante dans 10.10.52.0/24"
fi

# --- NetBox -------------------------------------------------------------------------------------------
_m10o_plage_fip() {
  netbox_api "ipam/ip-ranges/?limit=1000" \
    | jq -e '.results | map(select((.start_address | startswith("10.10.52.200/")) and (.end_address | startswith("10.10.52.249/")))) | length > 0' >/dev/null
}
check_cmd "NetBox : plage 10.10.52.200 - 10.10.52.249 déclarée" _m10o_plage_fip
