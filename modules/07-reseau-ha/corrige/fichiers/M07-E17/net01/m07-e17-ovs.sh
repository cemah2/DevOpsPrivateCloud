#!/usr/bin/env bash
# m07-e17-ovs.sh — M07-E17 (PLAT-827) : sur net01, un « serveur » agrégé en LACP vers Open vSwitch,
# deux VLAN, deux postes d'accès et un miroir de port.
# Usage (root, sur net01) : m07-e17-ovs.sh monter | demonter | etat
# Idempotent : « monter » reconstruit ce qui manque, ne casse pas ce qui existe.
#
#   ns-srv (serveur)                     espace racine de net01 : Open vSwitch
#   ┌──────────────────────┐             ┌──────────────────────────────────────────────┐
#   │ bond0 802.3ad        │ veth-s1 ═══ veth-w1 ┐                                       │
#   │  ├ bond0.10 .10.1    │ veth-s2 ═══ veth-w2 ┴ bond-srv (lacp=active, trunks=10,20)  │
#   │  └ bond0.20 .20.1    │             │                  br-lab                       │
#   └──────────────────────┘             │ veth-w10 (tag=10) ══ veth-a10 [ns-a10 .10.2]  │
#                                        │ veth-w20 (tag=20) ══ veth-a20 [ns-a20 .20.2]  │
#                                        │ mir0 (interne) ← miroir de bond-srv           │
#                                        └──────────────────────────────────────────────┘
# Adresses de laboratoire (172.16.10.0/24, 172.16.20.0/24) : internes à net01, jamais routées.
# Pourquoi OVS dans l'espace RACINE : ovs-vswitchd ne voit que les interfaces de son propre espace
# de noms ; on y laisse donc le côté « commutateur » des paires veth, et on range les machines
# (serveur, postes) dans leurs espaces de noms.
set -euo pipefail

PONT=br-lab
BOND=bond-srv

existe_ns() { ip netns list | grep -qw "$1"; }

veth() { # veth <côté commutateur> <côté machine> <espace de noms>
  ip link show "$1" >/dev/null 2>&1 && return 0
  ip link add "$1" type veth peer name "$2"
  ip link set "$2" netns "$3"
  ip link set "$1" up
}

monter() {
  for ns in ns-srv ns-a10 ns-a20; do existe_ns "$ns" || ip netns add "$ns"; done

  veth veth-w1 veth-s1 ns-srv
  veth veth-w2 veth-s2 ns-srv
  veth veth-w10 veth-a10 ns-a10
  veth veth-w20 veth-a20 ns-a20

  # Côté serveur : bond Linux 802.3ad (LACP), contrôle du lien toutes les 100 ms, LACP rapide.
  if ! ip netns exec ns-srv ip link show bond0 >/dev/null 2>&1; then
    ip netns exec ns-srv ip link add bond0 type bond mode 802.3ad miimon 100 lacp_rate fast \
      xmit_hash_policy layer3+4
    for p in veth-s1 veth-s2; do
      ip netns exec ns-srv ip link set "$p" down
      ip netns exec ns-srv ip link set "$p" master bond0
    done
    ip netns exec ns-srv ip link set bond0 up
    for v in 10 20; do
      ip netns exec ns-srv ip link add link bond0 name "bond0.$v" type vlan id "$v"
      ip netns exec ns-srv ip addr add "172.16.$v.1/24" dev "bond0.$v"
      ip netns exec ns-srv ip link set "bond0.$v" up
    done
  fi
  for v in 10 20; do
    ip netns exec "ns-a$v" ip link set "veth-a$v" up
    ip netns exec "ns-a$v" ip addr replace "172.16.$v.2/24" dev "veth-a$v"
  done

  # Côté commutateur : le pont, le bond OVS en LACP actif, les ports d'accès, le miroir.
  ovs-vsctl --may-exist add-br "$PONT"
  ovs-vsctl --may-exist add-bond "$PONT" "$BOND" veth-w1 veth-w2 lacp=active \
    -- set port "$BOND" bond_mode=balance-tcp other_config:lacp-time=fast trunks=10,20
  ovs-vsctl --may-exist add-port "$PONT" veth-w10 tag=10
  ovs-vsctl --may-exist add-port "$PONT" veth-w20 tag=20
  ovs-vsctl --may-exist add-port "$PONT" mir0 -- set interface mir0 type=internal
  ip link set mir0 up
  # Miroir : tout ce qui entre ou sort par le bond est COPIÉ vers mir0 (sonde, tcpdump).
  if ! ovs-vsctl --columns=name --bare list mirror | grep -qx miroir-srv; then
    ovs-vsctl -- --id=@b get port "$BOND" -- --id=@m get port mir0 \
      -- --id=@miroir create mirror name=miroir-srv select-src-port=@b select-dst-port=@b output-port=@m \
      -- set bridge "$PONT" mirrors=@miroir
  fi
  ip link set "$PONT" up
}

demonter() {
  ovs-vsctl --if-exists clear bridge "$PONT" mirrors
  ovs-vsctl --if-exists del-br "$PONT"
  for p in veth-w1 veth-w2 veth-w10 veth-w20; do ip link del "$p" 2>/dev/null || true; done
  for ns in ns-srv ns-a10 ns-a20; do ip netns del "$ns" 2>/dev/null || true; done
}

etat() {
  ovs-vsctl show
  echo "--- LACP (côté OVS)"
  ovs-appctl lacp/show "$BOND" || true
  echo "--- bond (côté OVS)"
  ovs-appctl bond/show "$BOND" || true
  echo "--- bond (côté serveur)"
  ip netns exec ns-srv cat /proc/net/bonding/bond0 || true
}

case "${1:-}" in
  monter) monter ;;
  demonter) demonter ;;
  etat) etat ;;
  *) echo "Usage : $0 monter|demonter|etat" >&2; exit 2 ;;
esac
