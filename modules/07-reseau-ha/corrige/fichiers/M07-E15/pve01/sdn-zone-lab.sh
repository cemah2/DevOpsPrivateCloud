#!/usr/bin/env bash
# sdn-zone-lab.sh — M07-E15 (CHG-825) : MTU 9000 sur la zone SDN « lab » de pve01.
# À lancer EN ROOT sur pve01, APRÈS le passage de vmbr1 à 9000 (une VNet ne peut pas dépasser le
# MTU du pont qui la porte). Idempotent. Retour arrière : ./sdn-zone-lab.sh --annuler
#
# La zone porte le MTU de TOUTES ses VNets : les ponts deviennent CAPABLES de 9000. Les VMs, elles,
# gardent 1500 tant que leur carte n'a pas « mtu=9000 » (ou « mtu=1 » : MTU du pont) : seules
# celles des VLAN 30, 31 et 51 le reçoivent (PLAN §4.9).
set -euo pipefail

zone=lab
mtu=9000
if [[ "${1:-}" == "--annuler" ]]; then
  # Revenir au MTU par défaut de la zone (option supprimée).
  pvesh set "/cluster/sdn/zones/$zone" --delete mtu
else
  pvesh set "/cluster/sdn/zones/$zone" --mtu "$mtu"
fi
# Appliquer la configuration SDN en attente (équivalent du bouton « Apply » de l'interface).
pvesh set /cluster/sdn
sleep 3
pvesh get "/cluster/sdn/zones/$zone" --output-format json
for vnet in vstopub vstoclu vostun vsandbox; do
  printf '%-10s mtu %s\n' "$vnet" "$(cat "/sys/class/net/$vnet/mtu" 2>/dev/null || echo '?')"
done
