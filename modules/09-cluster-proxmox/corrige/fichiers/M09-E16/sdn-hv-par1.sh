#!/usr/bin/env bash
# sdn-hv-par1.sh — SDN du cluster hv-par1 (M09-E16) : zone VLAN « invites » + zone EVPN « evhv ».
# Rejouable : un objet existant n'est pas recréé. À lancer en root sur hv01, APRÈS la préparation
# des nœuds (frr-pythontools, frr activé, « source /etc/network/interfaces.d/* ») : voir --preparer.
#
#   ./sdn-hv-par1.sh --preparer   prépare les trois nœuds (paquets, service, inclusion)
#   ./sdn-hv-par1.sh              déclare les objets puis APPLIQUE (recharge le réseau des nœuds)
#
# ⚠️ L'application recharge le réseau de tous les nœuds (ifreload). Garde une console série ouverte
# (qm terminal 2091 depuis pve01). Retour arrière : supprimer l'objet fautif, réappliquer.
set -euo pipefail

NOEUDS=(hv01 hv02 hv03)
PAIRS="10.10.10.51,10.10.10.52,10.10.10.53" # adresses MGMT : le réseau sous-jacent du VXLAN

sur() { local n="$1"; shift; if [[ "$n" == "$(hostname -s)" ]]; then bash -c "$*"; else ssh -o BatchMode=yes "root@$n" -- "$@"; fi; }

if [[ "${1:-}" == --preparer ]]; then
  for n in "${NOEUDS[@]}"; do
    echo "== $n"
    # frr et frr-pythontools des dépôts Proxmox (PAS deb.frrouting.org : version testée avec le SDN).
    sur "$n" 'DEBIAN_FRONTEND=noninteractive apt-get install -y frr frr-pythontools >/dev/null && systemctl enable --now frr'
    sur "$n" 'grep -qx "source /etc/network/interfaces.d/\*" /etc/network/interfaces \
              || echo "source /etc/network/interfaces.d/*" >> /etc/network/interfaces'
    # Aucune configuration FRR héritée : le SDN génère /etc/frr/frr.conf.
    sur "$n" 'vtysh -c "show running-config" | grep -E "^router bgp" || echo "   pas de BGP préexistant"'
  done
  exit 0
fi
[[ $# -eq 0 ]] || { echo "Usage : $0 [--preparer]" >&2; exit 2; }

existe() { pvesh get "$1" >/dev/null 2>&1; }
creer() { # creer CHEMIN_OBJET CHEMIN_COLLECTION ARGS… — crée seulement si l'objet n'existe pas
  local obj="$1" coll="$2"; shift 2
  if existe "$obj"; then echo "== $obj existe"; else pvesh create "$coll" "$@"; fi
}

# --- Zone VLAN des invités -------------------------------------------------------------------------
creer /cluster/sdn/zones/invites /cluster/sdn/zones --zone invites --type vlan --bridge vmbr1 --ipam pve
creer /cluster/sdn/vnets/vinv99 /cluster/sdn/vnets --vnet vinv99 --zone invites --tag 99 \
  --alias "SANDBOX (VLAN 99, DHCP Kea)"

# --- EVPN : contrôleur, zone, VNets, sous-réseaux ------------------------------------------------
creer /cluster/sdn/controllers/evpnhv /cluster/sdn/controllers --controller evpnhv --type evpn \
  --asn 65090 --peers "$PAIRS"
creer /cluster/sdn/zones/evhv /cluster/sdn/zones --zone evhv --type evpn --controller evpnhv \
  --vrf-vxlan 10090 --mtu 1450 --ipam pve
creer /cluster/sdn/vnets/vevpn1 /cluster/sdn/vnets --vnet vevpn1 --zone evhv --tag 11001 --alias "EVPN 10.90.1.0/24"
creer /cluster/sdn/vnets/vevpn2 /cluster/sdn/vnets --vnet vevpn2 --zone evhv --tag 11002 --alias "EVPN 10.90.2.0/24"
# Identifiant d'un sous-réseau dans l'API : <zone>-<adresse>-<préfixe>
creer /cluster/sdn/vnets/vevpn1/subnets/evhv-10.90.1.0-24 /cluster/sdn/vnets/vevpn1/subnets \
  --subnet 10.90.1.0/24 --type subnet --gateway 10.90.1.1
creer /cluster/sdn/vnets/vevpn2/subnets/evhv-10.90.2.0-24 /cluster/sdn/vnets/vevpn2/subnets \
  --subnet 10.90.2.0/24 --type subnet --gateway 10.90.2.1

# --- Application ---------------------------------------------------------------------------------
pvesh set /cluster/sdn
sleep 10
for n in "${NOEUDS[@]}"; do
  echo "== $n"
  sur "$n" 'ip -br link show vinv99; ip -br addr show vevpn1; ip -br addr show vevpn2'
  sur "$n" 'vtysh -c "show bgp l2vpn evpn summary"'
done
