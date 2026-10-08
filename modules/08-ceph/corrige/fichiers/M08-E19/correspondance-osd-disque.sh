#!/usr/bin/env bash
# correspondance-osd-disque.sh — M08-E19 : pour un hôte Ceph, de chaque OSD au disque virtuel de
# Proxmox (OSD → périphérique → numéro de série → ligne scsiN de la VM → volume). LECTURE SEULE.
# Depuis adm01 : ./correspondance-osd-disque.sh ceph04 2084
# Les disques d'OSD sont créés par le module vm-noeud avec un numéro de série explicite
# (« ceph04-ssd1 », « ceph04-ssd2 », « ceph04-hdd1 », M08-E02) : il apparaît dans l'invité
# (lsblk -o SERIAL) ET dans la configuration Proxmox (serial=…). C'est la clé de la correspondance.
# shellcheck disable=SC2029  # développement local voulu dans les commandes ssh
set -euo pipefail

HOTE="${1:?Usage : $0 <hôte> <VMID>}"
VMID="${2:?Usage : $0 <hôte> <VMID>}"
ADMIN=${WB_CEPH_ADMIN:-ceph01}
PVE=${WB_PVE_HOST:-pve01}
c() { ssh -o BatchMode=yes "$ADMIN" "sudo ceph $(printf '%q ' "$@")"; }

config_vm="$(ssh -o BatchMode=yes "$PVE" "qm config $VMID")"
series="$(ssh -o BatchMode=yes "$HOTE" 'lsblk -dno NAME,SERIAL')"

printf '%-8s %-6s %-6s %-14s %-7s %s\n' OSD CLASSE DISQUE SERIE PROXMOX VOLUME
for id in $(c osd ls-tree "$HOTE"); do
  meta="$(c osd metadata "$id" --format json)"
  dev="$(jq -r '.devices // "?"' <<<"$meta")"
  classe="$(c osd crush get-device-class "osd.$id" || echo '?')"
  serie="$(awk -v d="$dev" '$1 == d {print $2}' <<<"$series")"
  ligne="$(grep -E "^(scsi|virtio|sata)[0-9]+: .*serial=${serie}(,|$)" <<<"$config_vm" || true)"
  printf '%-8s %-6s %-6s %-14s %-7s %s\n' "osd.$id" "$classe" "$dev" "${serie:-?}" \
    "${ligne%%:*}" "$(cut -d' ' -f2 <<<"$ligne" | cut -d, -f1)"
done
