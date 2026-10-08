# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : pas d'expansion voulue
#
# check-E16.sh — M09-E16 : SDN du cluster : zones, VNets et EVPN
# À lancer depuis adm01. Lecture seule (configuration SDN par l'API, interfaces, « vtysh -c show … »).

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E16 — SDN du cluster : zones, VNets et EVPN"
require_cmd jq

_m09o_z="$(_m09o_pvesh /cluster/sdn/zones)"
_m09o_v="$(_m09o_pvesh /cluster/sdn/vnets)"
_m09o_k="$(_m09o_pvesh /cluster/sdn/controllers)"

check_cmd "zone invites : type vlan sur le pont vmbr1" _m09o_json "$_m09o_z" \
  'map(select(.zone == "invites"))[0] | .type == "vlan" and .bridge == "vmbr1"'
check_cmd "VNet vinv99 : zone invites, étiquette 99" _m09o_json "$_m09o_v" \
  'map(select(.vnet == "vinv99"))[0] | .zone == "invites" and ((.tag | tostring) == "99")'
check_cmd "contrôleur evpnhv : EVPN, AS 65090, pairs 10.10.10.51-53" _m09o_json "$_m09o_k" \
  'map(select(.controller == "evpnhv"))[0] | .type == "evpn" and ((.asn | tostring) == "65090")
   and (.peers | test("10\\.10\\.10\\.51")) and (.peers | test("10\\.10\\.10\\.52")) and (.peers | test("10\\.10\\.10\\.53"))'
check_cmd "zone evhv : EVPN, contrôleur evpnhv, VRF 10090, MTU 1450" _m09o_json "$_m09o_z" \
  'map(select(.zone == "evhv"))[0] | .type == "evpn" and .controller == "evpnhv"
   and ((."vrf-vxlan" | tostring) == "10090") and ((.mtu | tostring) == "1450")'
check_cmd "VNets vevpn1 (11001) et vevpn2 (11002) dans la zone evhv" _m09o_json "$_m09o_v" \
  '(map(select(.vnet == "vevpn1" and .zone == "evhv" and ((.tag | tostring) == "11001"))) | length == 1)
   and (map(select(.vnet == "vevpn2" and .zone == "evhv" and ((.tag | tostring) == "11002"))) | length == 1)'
for _m09o_i in 1 2; do
  check_cmd "vevpn$_m09o_i : sous-réseau 10.90.$_m09o_i.0/24, passerelle 10.90.$_m09o_i.1" _m09o_json \
    "$(_m09o_pvesh "/cluster/sdn/vnets/vevpn$_m09o_i/subnets")" \
    'map(select((((.cidr // "") == $c) or ((.subnet // "") | endswith($id))) and .gateway == $g)) | length == 1' \
    --arg c "10.90.$_m09o_i.0/24" --arg id "10.90.$_m09o_i.0-24" --arg g "10.90.$_m09o_i.1"
done
# Une modification non appliquée apparaît avec un champ « state » dans la vue « pending ».
_m09o_rien_en_attente() {
  local c j
  for c in zones vnets controllers; do
    j="$(_m09o_pvesh "/cluster/sdn/$c" --pending 1)"
    _m09o_json "$j" 'map(select(.state != null)) | length == 0' || return 1
  done
}
check_cmd "configuration SDN appliquée : rien en attente (zones, VNets, contrôleurs)" _m09o_rien_en_attente

for _m09o_n in $_M09O_NOEUDS; do
  check_ssh "$_m09o_n : interfaces vinv99, vevpn1 et vevpn2 présentes" "$_m09o_n" \
    'ip link show vinv99 >/dev/null && ip link show vevpn1 >/dev/null && ip link show vevpn2 >/dev/null'
  check_cmd "$_m09o_n : deux sessions BGP EVPN établies" _m09o_json \
    "$(_m09o_hv "$_m09o_n" "vtysh -c 'show bgp l2vpn evpn summary json'")" \
    '[.. | objects | select(has("state")) | .state | select(. == "Established")] | length >= 2'
done

_m09o_c="$(_m09o_conf 101)"
check_output "app01 (101) branchée sur le VNet vinv99" '^net0: .*bridge=vinv99' echo "$_m09o_c"
_m09o_res="$(_m09o_ressources)"
check_output "evpn01 (140) branchée sur vevpn1" '^net0: .*bridge=vevpn1' echo "$(_m09o_conf 140)"
check_output "evpn02 (141) branchée sur vevpn2" '^net0: .*bridge=vevpn2' echo "$(_m09o_conf 141)"
check_cmd "evpn01 et evpn02 tournent sur deux nœuds différents" _m09o_json "$_m09o_res" \
  '(map(select(.vmid == 140))[0]) as $a | (map(select(.vmid == 141))[0]) as $b
   | $a != null and $b != null and $a.status == "running" and $b.status == "running" and $a.node != $b.node'
