#!/usr/bin/env bash
# migrer-vm-vnet.sh — Bascule une interface de VM d'un bridge taggé vers un VNet SDN,
# en conservant le modèle, la MAC et les autres options (M00-E28).
# Usage : migrer-vm-vnet.sh <VMID> <VNET> [netN]      ex. migrer-vm-vnet.sh 1002 vinfra
# Retour arrière : qm set <VMID> --<netN> "$(cat /var/lib/workbook/sdn-<VMID>-<netN>.avant)"
set -euo pipefail

[[ $# -ge 2 ]] || { echo "Usage : $0 <VMID> <VNET> [netN]" >&2; exit 2; }
vmid="$1"; vnet="$2"; iface="${3:-net0}"

pvesh get "/cluster/sdn/vnets/$vnet" >/dev/null 2>&1 || { echo "VNet $vnet inconnu" >&2; exit 1; }
ip link show dev "$vnet" >/dev/null 2>&1 || { echo "VNet $vnet non appliqué sur l'hôte (pvesh set /cluster/sdn ?)" >&2; exit 1; }

avant="$(qm config "$vmid" --current | sed -n "s/^${iface}: //p")"
[[ -n "$avant" ]] || { echo "VM $vmid : pas d'interface $iface" >&2; exit 1; }

mkdir -p /var/lib/workbook
printf '%s\n' "$avant" > "/var/lib/workbook/sdn-${vmid}-${iface}.avant"

# Retire bridge= et tag=, garde tout le reste (modèle=MAC en tête, firewall, link_down…)
apres="$(tr ',' '\n' <<<"$avant" | grep -Ev '^(bridge|tag)=' | paste -sd, -),bridge=${vnet}"

echo "VM $vmid $iface"
echo "  avant : $avant"
echo "  après : $apres"
read -r -p "Appliquer ? [o/N] " rep
[[ "$rep" == "o" ]] || { echo "Abandon."; exit 0; }

qm set "$vmid" "--${iface}" "$apres"
echo "Fait. Vérifie maintenant : passerelle, DNS, SSH. Sauvegarde de l'ancienne valeur :"
echo "  /var/lib/workbook/sdn-${vmid}-${iface}.avant"
