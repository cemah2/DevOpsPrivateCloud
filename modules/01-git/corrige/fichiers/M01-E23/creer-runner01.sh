#!/usr/bin/env bash
# =============================================================================
# creer-runner01.sh — clone runner01 (VMID 1007) depuis le template 9000 (M01-E23)
# À lancer en root sur pve01. Même procédure que git01 (M01-E04) et le socle (M00-E12).
#
# Usage : ./creer-runner01.sh [ORDRE-DE-DÉMARRAGE]
#   ORDRE : position dans l'ordre de démarrage, APRÈS celle de git01
#           (qm config 1004 | grep startup) ; défaut 5.
# =============================================================================
set -euo pipefail

VMID=1007
NOM=runner01
IP=10.10.20.15
GW=10.10.20.1
ORDRE="${1:-5}"
STO_SYS="${WB_STORAGE_NVME:-local-nvme}"

if qm status "$VMID" >/dev/null 2>&1 || pct status "$VMID" >/dev/null 2>&1; then
  echo "VMID $VMID déjà utilisé : rien à faire (vérifie qu'il s'agit bien de $NOM)." >&2
  exit 1
fi

ordre_git01="$(qm config 1004 2>/dev/null | sed -nE 's/^startup:.*order=([0-9]+).*/\1/p')"
if [[ -n "$ordre_git01" ]] && ((ORDRE <= ordre_git01)); then
  echo "L'ordre $ORDRE ne place pas $NOM après git01 (ordre $ordre_git01)." >&2
  exit 1
fi

qm clone 9000 "$VMID" --name "$NOM" --full 1 --pool lab --storage "$STO_SYS"
qm set "$VMID" \
  --cores 2 --memory 4096 \
  --tags "socle;role-runner" \
  --net0 "virtio,bridge=vinfra" \
  --ipconfig0 "ip=${IP}/24,gw=${GW}" \
  --onboot 1 --startup "order=${ORDRE}"
qm disk resize "$VMID" scsi0 30G
qm start "$VMID"

for i in $(seq 1 60); do
  if qm guest cmd "$VMID" ping >/dev/null 2>&1; then
    echo "$NOM : agent QEMU opérationnel (après ~$((i * 5)) s)."
    exit 0
  fi
  sleep 5
done
echo "$NOM : l'agent ne répond pas après 5 min. Regarde la console : qm terminal $VMID" >&2
exit 1
