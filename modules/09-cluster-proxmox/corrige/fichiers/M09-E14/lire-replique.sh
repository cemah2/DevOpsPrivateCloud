#!/usr/bin/env bash
# lire-replique.sh — lit le dernier état répliqué d'un disque de VM sur un nœud CIBLE, sans démarrer
# la VM (M09-E14, mesure du RPO). Lecture seule pour la VM : on clone l'instantané de réplication,
# on monte le clone en lecture seule, on affiche le fichier demandé, puis on DÉTRUIT le clone
# (un clone restant bloquerait la réplication suivante : l'instantané ne pourrait plus être supprimé).
#
# Usage (en root sur le nœud cible) : lire-replique.sh VMID CHEMIN_DANS_L_INVITÉ [PARTITION]
#   ex. lire-replique.sh 110 /var/tmp/horodatage.log 1
set -euo pipefail

[[ $# -ge 2 && $# -le 3 ]] || { echo "Usage : $0 VMID CHEMIN [PARTITION]" >&2; exit 2; }
vmid="$1"; chemin="$2"; part="${3:-1}"
zvol="tank/vm-$vmid-disk-0"
clone="tank/lecture-$vmid-$$"
point="/mnt/lecture-$vmid-$$"

instantane="$(zfs list -H -t snapshot -o name -s creation "$zvol" | grep '@__replicate_' | tail -n 1)"
[[ -n "$instantane" ]] || { echo "aucun instantané de réplication pour $zvol sur ce nœud" >&2; exit 1; }
echo "instantané : $instantane (créé le $(zfs get -H -o value creation "$instantane"))"

nettoyer() {
  mountpoint -q "$point" && umount "$point"
  rmdir "$point" 2>/dev/null || true
  zfs list -H "$clone" >/dev/null 2>&1 && zfs destroy "$clone"
}
trap nettoyer EXIT

zfs clone -o readonly=on "$instantane" "$clone"
udevadm settle
mkdir -p "$point"
mount -o ro,noload "/dev/zvol/$clone-part$part" "$point" 2>/dev/null \
  || mount -o ro "/dev/zvol/$clone-part$part" "$point"
tail -n 3 "$point$chemin"
