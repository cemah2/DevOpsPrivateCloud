#!/usr/bin/env bash
# creer-git01.sh — crée la VM 1004 git01 depuis adm01, par l'alias SSH pve01 (M01-E04).
# Usage : creer-git01.sh            (stockage : $WB_STORAGE_NVME, défaut local-nvme)
# Ne fait rien si le VMID 1004 existe déjà. N'agit que dans le pool lab.
set -euo pipefail

VMID=1004
NOM=git01
IP=10.10.20.12
STOCKAGE="${WB_STORAGE_NVME:-local-nvme}"
MEMOIRE=8192

# shellcheck disable=SC2029  # expansion côté client voulue (VMID, options)
pve() { ssh pve01 "$@"; }

# 1. Garde-fous : VMID libre, adresse libre, mémoire disponible
if pve qm status "$VMID" >/dev/null 2>&1; then
  echo "Refus : le VMID $VMID existe déjà." >&2; exit 1
fi
if ping -c 2 -W 2 "$IP" >/dev/null 2>&1; then
  echo "Refus : $IP répond déjà au ping (adresse occupée)." >&2; exit 1
fi
dispo_mo=$(pve "awk '/^MemAvailable:/ {print int(\$2/1024)}' /proc/meminfo")
echo "Mémoire disponible sur pve01 : ${dispo_mo} Mo (nécessaire : ${MEMOIRE} Mo + marge)"
if (( dispo_mo < MEMOIRE + 2048 )); then
  echo "Refus : marge mémoire insuffisante sur pve01 (arrête d'abord un profil lourd)." >&2; exit 1
fi

# 2. Clone complet du template, rangé dans le pool lab
pve qm clone 9000 "$VMID" --name "$NOM" --pool lab --full 1 --storage "$STOCKAGE"

# 3. Matériel, réseau (VNet SDN vinfra), cloud-init, démarrage après dns01 (ordre 2)
pve qm set "$VMID" --cores 4 --memory "$MEMOIRE" --balloon 0 --tags "socle;role-gitlab" \
  --net0 virtio,bridge=vinfra --ipconfig0 "ip=${IP}/24,gw=10.10.20.1" \
  --onboot 1 --startup order=4
pve qm disk resize "$VMID" scsi0 60G

# 4. Démarrage et attente de l'agent QEMU (installé par le vendor-data au premier démarrage)
pve qm start "$VMID"
for _ in $(seq 1 60); do
  if pve qm guest cmd "$VMID" ping >/dev/null 2>&1; then echo "Agent QEMU : OK"; break; fi
  sleep 5
done
pve qm config "$VMID" | grep -E '^(name|cores|memory|balloon|net0|ipconfig0|tags|onboot|startup|scsi0):'
