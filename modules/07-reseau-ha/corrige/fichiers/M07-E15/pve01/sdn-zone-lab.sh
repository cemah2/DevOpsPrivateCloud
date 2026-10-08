#!/usr/bin/env bash
# sdn-zone-lab.sh — M07-E15 (CHG-825) : MTU 9000 sur la zone SDN « lab » de pve01.
# À lancer EN ROOT sur pve01, APRÈS le passage de vmbr1 à 9000 (une VNet ne peut pas dépasser le
# MTU du pont qui la porte). Idempotent. Retour arrière : ./sdn-zone-lab.sh --annuler
#
# La zone porte le MTU de TOUTES ses VNets (le greffon VLAN écrit « mtu » dans le bloc de chaque
# pont de VNet) : les ponts deviennent CAPABLES de 9000. Les VMs, elles, gardent 1500 tant que leur
# carte n'a pas « mtu=9000 » (ou « mtu=1 » : MTU du pont) : seules celles des VLAN 30, 31 et 51 le
# reçoivent (PLAN §4.9).
#
# ⚠️ « pvesh set /cluster/sdn » applique TOUT ce qui est en attente dans le SDN et recharge le
# réseau de pve01 (ifreload -a) : le script refuse d'appliquer si d'autres changements SDN que
# celui de la zone « lab » sont en attente.
set -euo pipefail

zone=lab
mtu=9000

command -v jq >/dev/null || { echo "jq requis" >&2; exit 1; }

# Changements SDN en attente qui ne viennent pas de ce script (VNets, autres zones).
autres_attentes() {
  pvesh get /cluster/sdn/vnets --pending 1 --output-format json \
    | jq -r '.[] | select(.state != null) | "vnet \(.vnet) \(.state)"'
  pvesh get /cluster/sdn/zones --pending 1 --output-format json \
    | jq -r --arg z "$zone" '.[] | select(.state != null and .zone != $z) | "zone \(.zone) \(.state)"'
}

attente="$(autres_attentes)"
if [[ -n "$attente" ]]; then
  echo "Changements SDN en attente qui ne viennent pas de ce script :" >&2
  awk '{print "  " $0}' <<<"$attente" >&2
  echo "Applique-les ou annule-les d'abord, à la main : rien n'a été modifié." >&2
  exit 1
fi

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
for i in vmbr1.30 vmbr1.31 vmbr1.51; do
  printf '%-10s mtu %s\n' "$i" "$(cat "/sys/class/net/$i/mtu" 2>/dev/null || echo '?')"
done
