#!/usr/bin/env bash
# generer-ova.sh — fabrique l'OVA « legacy-rdv01 » livrée par InfoGér (M09-E23).
#
# Le workbook ne versionne pas d'image disque : ce script reconstruit l'export à partir de
# l'image cloud officielle de Debian 13 (vérifiée par sa somme SHA-512), en lui donnant la forme
# d'un export VMware : disque VMDK « streamOptimized » de 10 Gio, contrôleur LSI Logic, carte
# E1000, descripteur OVF 1.0, manifeste SHA-256, le tout dans une archive tar (.ova).
#
# Usage : generer-ova.sh [-i IMAGE.qcow2] [DOSSIER_SORTIE]
#   -i IMAGE.qcow2   image Debian 13 genericcloud déjà téléchargée (sinon : téléchargement)
#   DOSSIER_SORTIE   dossier où écrire legacy-rdv01.ova (défaut : dossier courant)
# Prérequis : qemu-img (paquet qemu-utils ; présent sur un nœud Proxmox VE), curl,
# sha512sum, sha256sum, tar, sed. Espace libre : environ 4 Gio pendant la génération.
# Rejouable : l'OVA existante est remplacée ; les fichiers intermédiaires sont effacés.
set -euo pipefail

URL_BASE="https://cloud.debian.org/images/cloud/trixie/latest"
IMAGE_NOM="debian-13-genericcloud-amd64.qcow2"
NOM_VM="legacy-rdv01"
CAPACITE_GIO=10
MODELE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${NOM_VM}.ovf.modele"

usage() { echo "Usage : $0 [-i IMAGE.qcow2] [DOSSIER_SORTIE]" >&2; exit 2; }

image=""
while getopts ":i:h" opt; do
  case "$opt" in
    i) image="$OPTARG" ;;
    h|*) usage ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -le 1 ]] || usage
sortie="${1:-.}"

for outil in qemu-img curl sha512sum sha256sum tar sed; do
  command -v "$outil" >/dev/null 2>&1 || { echo "outil manquant : $outil" >&2; exit 1; }
done
[[ -r "$MODELE" ]] || { echo "modèle OVF introuvable : $MODELE" >&2; exit 1; }
mkdir -p "$sortie"
sortie="$(cd "$sortie" && pwd)"

travail="$(mktemp -d "$sortie/.ova-XXXXXX")"
trap 'rm -rf "$travail"' EXIT

# --- 1. Image source, vérifiée ---------------------------------------------------------------
curl -fsSL --proto "=https" --proto-redir "=https" "$URL_BASE/SHA512SUMS" -o "$travail/SHA512SUMS"
attendue="$(awk -v n="$IMAGE_NOM" '$2 == n {print $1}' "$travail/SHA512SUMS")"
[[ -n "$attendue" ]] || { echo "somme de $IMAGE_NOM absente de SHA512SUMS" >&2; exit 1; }
if [[ -z "$image" ]]; then
  echo ">> téléchargement de $IMAGE_NOM"
  curl -fSL --proto "=https" --proto-redir "=https" --progress-bar "$URL_BASE/$IMAGE_NOM" -o "$travail/$IMAGE_NOM"
  image="$travail/$IMAGE_NOM"
fi
obtenue="$(sha512sum "$image" | awk '{print $1}')"
if [[ "$obtenue" != "$attendue" ]]; then
  echo "somme SHA-512 incorrecte pour $image (image corrompue ou plus ancienne que « latest »)" >&2
  exit 1
fi
echo ">> image vérifiée (SHA-512)"

# --- 2. Disque « VMware » : 10 Gio, VMDK streamOptimized ---------------------------------------
cp "$image" "$travail/source.qcow2"
qemu-img resize -q "$travail/source.qcow2" "${CAPACITE_GIO}G"
disque="${NOM_VM}-disk1.vmdk"
qemu-img convert -q -f qcow2 -O vmdk -o subformat=streamOptimized \
  "$travail/source.qcow2" "$travail/$disque"
rm -f "$travail/source.qcow2" "$travail/$IMAGE_NOM"

# --- 3. Descripteur OVF et manifeste ------------------------------------------------------------
taille="$(stat -c %s "$travail/$disque")"
sed -e "s/@DISQUE@/$disque/g" -e "s/@TAILLE_FICHIER@/$taille/g" -e "s/@CAPACITE_GIO@/$CAPACITE_GIO/g" \
  "$MODELE" >"$travail/$NOM_VM.ovf"
if grep -q '@[A-Z_]*@' "$travail/$NOM_VM.ovf"; then
  echo "variable non remplacée dans le descripteur OVF" >&2
  exit 1
fi
(
  cd "$travail"
  for f in "$NOM_VM.ovf" "$disque"; do
    printf 'SHA256(%s)= %s\n' "$f" "$(sha256sum "$f" | awk '{print $1}')"
  done
) >"$travail/$NOM_VM.mf"

# --- 4. Archive OVA : le descripteur en PREMIER (exigence OVF), puis le manifeste et le disque ---
tar -C "$travail" --format=ustar -cf "$travail/$NOM_VM.ova" "$NOM_VM.ovf" "$NOM_VM.mf" "$disque"
mv -f "$travail/$NOM_VM.ova" "$sortie/$NOM_VM.ova"

echo ">> OVA prête : $sortie/$NOM_VM.ova"
tar -tvf "$sortie/$NOM_VM.ova"
echo "SHA-256 : $(sha256sum "$sortie/$NOM_VM.ova" | awk '{print $1}')"
