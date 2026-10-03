#!/usr/bin/env bash
# =============================================================================
# creer-tpl-debian13.sh — fabrique le template 9000 tpl-debian13 (M00-E11)
# À lancer en root sur pve01. Idempotence minimale : refuse de toucher un VMID
# déjà pris. Prérequis : stockages et snippet en place, clé du lab générée.
# =============================================================================
set -euo pipefail

VMID=9000
NOM=tpl-debian13
STO_SYS="${WB_STORAGE_NVME:-local-nvme}"     # disque système et lecteur cloud-init
STO_BULK="${WB_STORAGE_BULK:-hdd-bulk}"      # snippets et images à importer
IMPORT_DIR=/mnt/hdd-bulk/import
IMAGE=debian-13-genericcloud-amd64.qcow2
URL_BASE=https://cloud.debian.org/images/cloud/trixie/latest
CLE_SSH=/root/.ssh/id_ed25519_lab.pub
SNIPPET="${STO_BULK}:snippets/vendor-debian13.yaml"

err() { echo "ERREUR : $*" >&2; exit 1; }

# --- Garde-fous ---------------------------------------------------------------
if qm status "$VMID" >/dev/null 2>&1 || pct status "$VMID" >/dev/null 2>&1; then
  err "le VMID $VMID est déjà utilisé"
fi
[[ -r "$CLE_SSH" ]] || err "clé publique $CLE_SSH absente (voir M00-E10)"
[[ -s "$(pvesm path "$SNIPPET")" ]] || err "snippet $SNIPPET absent"

# --- Image : téléchargement et vérification -----------------------------------
mkdir -p "$IMPORT_DIR"
cd "$IMPORT_DIR"
curl -fsSLO "$URL_BASE/SHA512SUMS"
if [[ ! -f "$IMAGE" ]]; then
  curl -fSLO "$URL_BASE/$IMAGE"
fi
grep " ${IMAGE}\$" SHA512SUMS | sha512sum -c - || err "somme SHA-512 incorrecte pour $IMAGE"
qemu-img info "$IMAGE"

# --- VM sans disque -------------------------------------------------------------
qm create "$VMID" \
  --name "$NOM" \
  --pool lab \
  --tags "debian13;template" \
  --description "Template Debian 13 genericcloud + cloud-init (M00-E11). Ne pas démarrer." \
  --ostype l26 \
  --cpu x86-64-v2-AES --cores 2 --memory 2048 \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr1 \
  --serial0 socket --vga serial0 \
  --agent enabled=1,fstrim_cloned_disks=1

# --- Import du disque et rattachement -------------------------------------------
qm disk import "$VMID" "$IMPORT_DIR/$IMAGE" "$STO_SYS"
VOLUME="$(qm config "$VMID" | awk '/^unused0:/ {print $2}')"
[[ -n "$VOLUME" ]] || err "volume importé introuvable (unused0)"
qm set "$VMID" --scsi0 "${VOLUME},discard=on,iothread=1,ssd=1" --boot order=scsi0
qm disk resize "$VMID" scsi0 8G

# --- Cloud-init ------------------------------------------------------------------
qm set "$VMID" \
  --ide2 "${STO_SYS}:cloudinit" \
  --ciuser admin \
  --sshkeys "$CLE_SSH" \
  --nameserver 10.10.20.10 \
  --searchdomain par1.medisphere.internal \
  --cicustom "vendor=${SNIPPET}"

qm cloudinit dump "$VMID" user

# --- Conversion en template (sans JAMAIS avoir démarré la VM) -----------------
qm template "$VMID"
qm config "$VMID"
