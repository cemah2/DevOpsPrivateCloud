#!/usr/bin/env bash
# nic-mtu.sh — M07-E15 (CHG-825) : carte trunk de gw01 (net1, sur vmbr1) en MTU 9000.
# À lancer EN ROOT sur pve01, dans la fenêtre du changement. Garde l'adresse MAC existante (sinon
# l'invité verrait une nouvelle carte). Usage : ./nic-mtu.sh [--annuler]
# ⚠️ Selon l'option « hotplug » de la VM, Proxmox applique le changement À CHAUD (la carte est
# débranchée puis rebranchée : coupure de TOUT le lab le temps que ens19 et ses sous-interfaces
# remontent) ou le met EN ATTENTE jusqu'au prochain démarrage (qm pending 1000).
set -euo pipefail

vmid=1000
mtu=9000
[[ "${1:-}" == "--annuler" ]] && mtu=1500

actuel="$(qm config "$vmid" | sed -n 's/^net1: //p')"
[[ -n "$actuel" ]] || { echo "net1 introuvable sur la VM $vmid" >&2; exit 1; }
echo "avant : net1: $actuel"
# Remplace (ou ajoute) l'option mtu=, garde tout le reste (modèle=MAC, bridge, firewall…).
nouveau="$(sed -E 's/(^|,)mtu=[0-9]+//' <<<"$actuel"),mtu=$mtu"
qm set "$vmid" --net1 "$nouveau"
echo "après : $(qm config "$vmid" | sed -n 's/^net1: /net1: /p')"
qm pending "$vmid" | grep -E 'net1' || true
