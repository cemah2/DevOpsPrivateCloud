# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E24.sh — M07-E24 « Une seconde passerelle : gw02 »
# Lecture seule : pve01 (root), gw01/gw02 (admin + sudo -n), API NetBox, DNS, copies de travail.
# Rejouable après M07-E25 : ce qui change légitimement avec VRRP (relais DHCP sur gw02, VIP portées
# par gw02 quand elle est maître) est alors contrôlé autrement.

# shellcheck source=_m07-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-production.sh"

title "M07-E24 — Une seconde passerelle : gw02"
require_cmd jq dig ssh diff
_m07p_charger
_m07p_charger_adresses gw01 gw02

title "La VM gw02 (1009)"
check_cmd "VM 1009 « gw02 » démarrée, dans le pool lab" _m07p_vm_jq 1009 '.name == "gw02" and .status == "running" and .pool == "lab"'
check_cmd "VM 1009 étiquetée socle et role-routeur" _m07p_vm_etiquettes 1009 socle role-routeur
check_ssh "VM 1009 : démarrage automatique" "$WB_PVE_HOST" "qm config 1009 | grep -q '^onboot: 1'"
check_cmd "VM 1009 : clone complet" _m07p_clone_complet 1009
# _m07_carte NETx — définition de la carte de 1009, si elle n'a pas d'étiquette VLAN.
_m07_carte() { _m07p_qm_config 1009 | grep "^$1:" | grep -v 'tag=' || true; }
check_output "net0 sur vmbr0 sans étiquette VLAN (WAN)" '^net0: [^ ]*bridge=vmbr0' _m07_carte net0
check_output "net1 sur vmbr1 sans étiquette VLAN, MTU 9000 (trunk)" '^net1: .*bridge=vmbr1.*mtu=9000' _m07_carte net1
check_cmd "plateforme/infra : gw02 décrite dans l'état socle (socle/gw02.tf, VMID 1009)" \
  bash -c 'grep -qsE "vm_id[[:space:]]*=[[:space:]]*1009" "$1"/socle/gw02.tf' _ "$_M07P_INFRA"

title "Nom et source de vérité"
check_dns "DNS : gw02.$_M07P_ZONE → 10.10.10.3" "gw02.$_M07P_ZONE" A '^10\.10\.10\.3$' 10.10.20.10
check_dns "DNS : PTR de 10.10.10.3 → gw02" 3.10.10.10.in-addr.arpa PTR "^gw02\\.par1\\.medisphere\\.internal\\.\$" 10.10.20.10
_m07_nb="$(netbox_api "ipam/ip-addresses/?virtual_machine=gw02&limit=50" 2>/dev/null || true)"
check_cmd "NetBox : gw02 a ses neuf adresses .3 (VLAN 10 à 99)" jq -e \
  '[.results[].address | select(test("^10\\.10\\.(10|20|30|40|50|52|60|70|99)\\.3/24$"))] | length == 9' <<<"${_m07_nb:-null}"

title "Adresses et noyau de gw02"
for _m07_v in "${_M07P_VLANS[@]}"; do
  check_cmd "gw02 porte 10.10.$_m07_v.3" _m07p_porte gw02 "10.10.$_m07_v.3"
done
# Une .1 sur gw02 n'est admise que portée par keepalived ET nulle part ailleurs (après M07-E25).
_m07_gw02_sans_1_hors_vrrp() {
  local v
  _m07p_adresses gw02 >/dev/null || return 1
  for v in "${_M07P_VLANS[@]}"; do
    if _m07p_porte gw02 "10.10.$v.1"; then
      remote gw02 "systemctl is-active -q keepalived" || return 1
      _m07p_porte gw01 "10.10.$v.1" && return 1
    fi
  done
  return 0
}
check_cmd "gw02 ne porte aucune adresse .1 hors VRRP (pas de conflit avec la passerelle du VLAN)" _m07_gw02_sans_1_hors_vrrp
for _m07_v in "${_M07P_VLANS[@]}"; do
  check_cmd "10.10.$_m07_v.1 portée par une seule passerelle" _m07p_vip_unique "10.10.$_m07_v.1" gw01 gw02
done
check_ssh_output "gw02 : routage IPv4 actif" gw02 '^1$' 'sysctl -n net.ipv4.ip_forward'
for _m07_h in gw01 gw02; do
  check_ssh "$_m07_h : routes de garde (unreachable) vers PAR2, LYO1 et les tunnels" "$_m07_h" \
    'r=$(ip -4 route show type unreachable); for p in 10.20.0.0/16 10.30.0.0/16 10.255.0.0/16; do grep -q "^unreachable $p " <<<"$r" || exit 1; done'
done

title "Une seule matrice, deux pare-feu"
check_cmd "matrice dans group_vars/role_routeur/pare_feu.yml" test -s "$_M07P_ANSIBLE/inventories/lab/group_vars/role_routeur/pare_feu.yml"
check_cmd "plus de matrice propre à gw01 (host_vars/gw01/pare_feu.yml)" bash -c '! test -e "$1/inventories/lab/host_vars/gw01/pare_feu.yml"' _ "$_M07P_ANSIBLE"
check_cmd "gw01 et gw02 chargent le même jeu de règles" _m07p_rulesets_identiques
check_ssh_output "gw02 : politique drop en entrée et en transit" gw02 'hook forward priority filter; policy drop' \
  'sudo -n nft list chain inet filter forward'

title "Services de gw02"
check_ssh "gw02 : chrony actif et synchronisé" gw02 'chronyc -n tracking | grep -q "Leap status *: Normal"'
check_port "gw02 : NTS-KE (4460) joignable depuis adm01" 10.10.10.3 4460
check_ssh "gw02 : certificat NTS au nom de gw02" gw02 \
  'sudo -n openssl x509 -noout -ext subjectAltName -in /etc/chrony/nts/gw02.crt | grep -q "gw02.par1.medisphere.internal"'
if _m07p_vm_tourne 2073; then
  check_cmd "gw02 : session BGP avec leaf01 (10.10.99.251) établie" _m07p_bgp_etabli gw02 10.10.99.251
else
  skip "gw02 : session BGP avec leaf01" "maquette arrêtée (VM 2073)"
fi
if remote gw02 "systemctl is-active -q keepalived" 2>/dev/null; then
  skip "gw02 : pas de relais DHCP" "VRRP en place (M07-E25) : le relais de gw02 est alors attendu"
else
  check_ssh "gw02 : pas de relais DHCP actif avant VRRP" gw02 \
    '! grep -Ehqs "^[[:space:]]*dhcp-relay=" /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf'
fi
