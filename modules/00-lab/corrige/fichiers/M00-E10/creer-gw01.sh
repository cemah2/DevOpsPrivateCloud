#!/usr/bin/env bash
# creer-gw01.sh — crée la VM 1000 gw01 sur pve01 (M00-E10).
# Ne fait que la création de la VM : l'installation de Debian se fait ensuite
# à la main, depuis la console noVNC.
# Usage : ./creer-gw01.sh <nom-de-l-iso-sur-hdd-bulk>
#   ex.   ./creer-gw01.sh debian-13.1.0-amd64-netinst.iso
set -euo pipefail

VMID=1000
ISO="${1:?Usage : $0 <fichier ISO présent dans hdd-bulk:iso/>}"
STO_SYS="${WB_STORAGE_NVME:-local-nvme}"
STO_ISO="${WB_STORAGE_BULK:-hdd-bulk}"

if qm status "$VMID" >/dev/null 2>&1 || pct status "$VMID" >/dev/null 2>&1; then
  echo "Le VMID $VMID est déjà utilisé : rien n'est fait." >&2
  exit 1
fi
if ! pvesm list "$STO_ISO" --content iso | grep -q "iso/${ISO}"; then
  echo "ISO introuvable : ${STO_ISO}:iso/${ISO}" >&2
  exit 1
fi

qm create "$VMID" \
  --name gw01 \
  --pool lab \
  --tags "reseau;socle" \
  --description "Routeur/pare-feu du lab MédiSphère (M00-E10). Installé à la main depuis l'ISO." \
  --ostype l26 \
  --cpu x86-64-v2-AES --cores 1 \
  --memory 2048 \
  --scsihw virtio-scsi-single \
  --scsi0 "${STO_SYS}:16,iothread=1,discard=on,ssd=1" \
  --ide2 "${STO_ISO}:iso/${ISO},media=cdrom" \
  --boot "order=scsi0;ide2" \
  --net0 virtio,bridge=vmbr0 \
  --net1 virtio,bridge=vmbr1 \
  --agent enabled=1 \
  --onboot 1 --startup order=1,up=30

qm config "$VMID"
echo "VM $VMID créée. Démarre-la (qm start $VMID) et installe Debian depuis la console."
