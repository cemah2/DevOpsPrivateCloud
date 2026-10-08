#!/usr/bin/env bash
# creer-tpl-ubuntu2404.sh — template 9050 « tpl-ubuntu2404 » depuis l'image cloud officielle
# d'Ubuntu 24.04, après vérification de sa signature (M11-E09). Même méthode que tpl-debian13 (M00).
#
#   root@pve01:~# ./creer-tpl-ubuntu2404.sh            (STOCKAGE=local-nvme DOSSIER=/mnt/hdd-bulk/import)
#
# Chaîne de confiance : clé « UEC Image Automatic Signing Key » dont l'EMPREINTE est écrite ici
# (vérifiée sur la page « Verifying Ubuntu cloud images » ET sur keyserver.ubuntu.com) → signature
# de SHA256SUMS → empreinte de l'image. Trousseau GnuPG temporaire : rien n'est ajouté à celui de root.
# Refuse de toucher à une VM 9050 existante (supprime-la toi-même si tu veux reconstruire).
set -euo pipefail

VMID=9050
NOM=tpl-ubuntu2404
STOCKAGE="${STOCKAGE:-local-nvme}"
DOSSIER="${DOSSIER:-/mnt/hdd-bulk/import}"
BASE=https://cloud-images.ubuntu.com/releases/noble/release
IMAGE=ubuntu-24.04-server-cloudimg-amd64.img
EMPREINTE_CLE=D2EB44626FDDC30B513D5BB71A5D6C4C7DB87C81   # UEC Image Automatic Signing Key

erreur() { printf 'creer-tpl-ubuntu2404 : %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || erreur "à lancer en root sur pve01"
if qm status "$VMID" >/dev/null 2>&1; then erreur "la VM $VMID existe déjà"; fi

install -d -m 755 "$DOSSIER"
cd "$DOSSIER"
gnupg="$(mktemp -d)"
trap 'rm -rf "$gnupg"' EXIT

dl() { curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' -o "$2" "$1"; }
dl "$BASE/SHA256SUMS" SHA256SUMS
dl "$BASE/SHA256SUMS.gpg" SHA256SUMS.gpg

gpg --homedir "$gnupg" --quiet --keyserver hkps://keyserver.ubuntu.com --recv-keys "$EMPREINTE_CLE"
# VALIDSIG <empreinte> … : la signature est bonne ET faite par CETTE clé (pas seulement « une » clé).
gpg --homedir "$gnupg" --status-fd 1 --verify SHA256SUMS.gpg SHA256SUMS 2>/dev/null \
  | grep -q "^\[GNUPG:\] VALIDSIG $EMPREINTE_CLE " || erreur "signature de SHA256SUMS invalide ou d'une autre clé"

if [[ ! -f "$IMAGE" ]] || ! sha256sum -c --ignore-missing --status SHA256SUMS; then
  dl "$BASE/$IMAGE" "$IMAGE"
fi
grep -q " \*\?$IMAGE\$" SHA256SUMS || erreur "$IMAGE absente de SHA256SUMS"
sha256sum -c --ignore-missing SHA256SUMS || erreur "empreinte de $IMAGE incorrecte"

qm create "$VMID" --name "$NOM" --pool lab --tags "template;ubuntu2404" \
  --ostype l26 --cores 2 --memory 2048 --cpu x86-64-v2-AES \
  --scsihw virtio-scsi-single --net0 virtio,bridge=vsandbox \
  --serial0 socket --vga serial0 --agent enabled=1
qm disk import "$VMID" "$DOSSIER/$IMAGE" "$STOCKAGE"
volume="$(qm config "$VMID" | sed -n 's/^unused0: //p')"
[[ -n "$volume" ]] || erreur "volume importé introuvable (unused0)"
qm set "$VMID" --scsi0 "$volume,discard=on,iothread=1,ssd=1" --boot order=scsi0 \
  --ide2 "$STOCKAGE:cloudinit" --ciuser admin
qm template "$VMID"
echo "Template $VMID $NOM créé depuis $IMAGE (signature et empreinte vérifiées)."
