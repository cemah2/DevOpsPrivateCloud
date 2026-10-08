# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E17.sh — M07-E17 : Open vSwitch : bonds LACP, VLAN et miroir de port
# À lancer depuis adm01, net01 démarrée. Lecture seule (pings entre espaces de noms de net01).

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E17 — Open vSwitch : bonds LACP, VLAN et miroir de port"

check_ssh "net01 : pont OVS br-lab" net01 'sudo -n ovs-vsctl br-exists br-lab'
check_ssh "net01 : bond-srv en LACP actif, deux membres" net01 \
  '[ "$(sudo -n ovs-vsctl get port bond-srv lacp)" = active ] && [ "$(sudo -n ovs-vsctl get port bond-srv interfaces | tr "," "\n" | wc -l)" = 2 ]'
check_ssh "net01 : LACP négocié côté OVS (lacp_status: negotiated)" net01 \
  'sudo -n ovs-appctl bond/show bond-srv | grep -q "lacp_status: negotiated"'
check_ssh "net01 : les deux membres de bond-srv sont activés" net01 \
  '[ "$(sudo -n ovs-appctl bond/show bond-srv | grep -c "^member .*: enabled")" = 2 ]'
check_ssh "net01 : bond-srv transporte les VLAN 10 et 20 (trunk)" net01 \
  'sudo -n ovs-vsctl get port bond-srv trunks | grep -q "10, 20"'
check_ssh "net01 : ports d'accès étiquetés 10 et 20" net01 \
  '[ "$(sudo -n ovs-vsctl get port veth-w10 tag)" = 10 ] && [ "$(sudo -n ovs-vsctl get port veth-w20 tag)" = 20 ]'
check_ssh "ns-srv : bond0 en 802.3ad avec deux membres" net01 \
  'f=$(sudo -n ip netns exec ns-srv cat /proc/net/bonding/bond0); grep -q "IEEE 802.3ad" <<<"$f" && [ "$(grep -c "^Slave Interface" <<<"$f")" = 2 ]'
check_ssh "ns-srv : les deux membres agrégés avec le même partenaire" net01 \
  'a=$(sudo -n ip netns exec ns-srv cat /proc/net/bonding/bond0 | sed -n "s/^Aggregator ID: //p" | sort -u); [ -n "$a" ] && [ "$(wc -l <<<"$a")" = 1 ]'
check_ssh "ns-a10 joint 172.16.10.1 (VLAN 10)" net01 'sudo -n ip netns exec ns-a10 ping -c 2 -W 1 172.16.10.1 >/dev/null'
check_ssh "ns-a20 joint 172.16.20.1 (VLAN 20)" net01 'sudo -n ip netns exec ns-a20 ping -c 2 -W 1 172.16.20.1 >/dev/null'
check_ssh "ns-a10 ne joint pas 172.16.20.1 (VLAN isolés)" net01 \
  '! sudo -n ip netns exec ns-a10 ping -c 2 -W 1 172.16.20.1 >/dev/null 2>&1'
check_ssh "net01 : un miroir copie le trafic de bond-srv vers mir0" net01 \
  'm=$(sudo -n ovs-vsctl --columns=select_src_port,select_dst_port,output_port --bare list mirror); p=$(sudo -n ovs-vsctl get port bond-srv _uuid); o=$(sudo -n ovs-vsctl get port mir0 _uuid); grep -q "$p" <<<"$m" && grep -q "$o" <<<"$m"'
check_ssh "net01 : construction relancée au démarrage (unité systemd activée)" net01 \
  'systemctl list-unit-files --state=enabled --no-legend | grep -E "\.service" | while read -r u _; do systemctl cat "$u" 2>/dev/null | grep -q "^ExecStart=.*/usr/local/sbin/" && systemctl cat "$u" | grep -q "openvswitch" && echo "$u"; done | grep -q .'
