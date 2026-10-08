#!/usr/bin/env bash
# outils/publier-image.sh — publier une image officielle dans Glance, somme vérifiée de bout en
# bout (M10-E06, DEV-1106).
#
#   source officielle (HTTPS) → fichier de sommes publié par la distribution → fichier local
#   vérifié → envoi à Glance → somme SHA-512 calculée par Glance comparée à celle du fichier local.
#
# Usage : outils/publier-image.sh debian-13|rocky-10 [--format qcow2|raw]
#   --format raw : convertit avant l'envoi (qemu-img). C'est le format exigé quand Glance et Nova
#   sont sur Ceph (M10-E10) ; au palier 1 (stockage « file »), on publie en qcow2.
# Variables : OS_CLOUD (défaut medisphere-admin), DOSSIER (défaut ~/m10/images, effacé à la fin
#             sauf CONSERVER=1).
# L'image existe déjà sous ce nom ? Le script refuse (Glance accepte des doublons de nom, ce qui
# rend tout outil qui cherche « debian-13 » ambigu) : renomme ou supprime l'ancienne d'abord.
set -euo pipefail

export OS_CLOUD="${OS_CLOUD:-medisphere-admin}"
DOSSIER="${DOSSIER:-$HOME/m10/images}"
format="qcow2"

usage() { echo "Usage : $0 debian-13|rocky-10 [--format qcow2|raw]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
nom="$1"; shift
while (($# > 0)); do
  case "$1" in
    --format) format="${2:-}"; shift 2 || usage ;;
    *) usage ;;
  esac
done
[[ "$format" == qcow2 || "$format" == raw ]] || usage

case "$nom" in
  debian-13)
    base="https://cloud.debian.org/images/cloud/trixie/latest"
    fichier="debian-13-genericcloud-amd64.qcow2"
    sommes="SHA512SUMS"; outil="sha512sum"
    proprietes=(--property os_distro=debian --property os_version=13 --public)
    ;;
  rocky-10)
    base="https://dl.rockylinux.org/pub/rocky/10/images/x86_64"
    fichier="Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
    sommes="$fichier.CHECKSUM"; outil="sha256sum"
    # Partagée (shared) : visible seulement des projets membres qui ont ACCEPTÉ (étape suivante).
    proprietes=(--property os_distro=rocky --property os_version=10 --shared)
    ;;
  *) usage ;;
esac
# Propriétés communes : disque SCSI virtio (discard possible), agent QEMU attendu, famille Linux.
proprietes+=(--property hw_disk_bus=scsi --property hw_scsi_model=virtio-scsi
             --property hw_qemu_guest_agent=yes --property os_type=linux)

if openstack image show "$nom" -f value -c id >/dev/null 2>&1; then
  echo "Une image « $nom » existe déjà : rien n'est fait (voir l'en-tête du script)." >&2
  exit 1
fi

install -d -m 0700 "$DOSSIER"
cd "$DOSSIER"
if [[ "${CONSERVER:-0}" != 1 ]]; then
  trap 'rm -f "$DOSSIER/$fichier" "$DOSSIER/$sommes" "$DOSSIER/${fichier%.qcow2}.raw"' EXIT
fi

echo "1/5 Téléchargement depuis $base (TLS vérifié)…"
curl -fsSL --proto '=https' -o "$sommes" "$base/$sommes"
curl -fL --proto '=https' -o "$fichier" "$base/$fichier"

echo "2/5 Vérification de la somme publiée par la distribution ($outil)…"
"$outil" --check --ignore-missing "$sommes" | grep -F "$fichier: OK"

echo "3/5 Inspection : format, taille virtuelle, taille du fichier…"
qemu-img info "$fichier"
a_envoyer="$fichier"
if [[ "$format" == raw ]]; then
  a_envoyer="${fichier%.qcow2}.raw"
  echo "    Conversion en raw (taille virtuelle complète sur le disque local)…"
  qemu-img convert -p -f qcow2 -O raw "$fichier" "$a_envoyer"
fi
locale="$(sha512sum "$a_envoyer" | cut -d' ' -f1)"

echo "4/5 Envoi à Glance ($OS_CLOUD) : $nom, format $format…"
openstack image create "$nom" --file "$a_envoyer" --disk-format "$format" \
  --container-format bare "${proprietes[@]}" -f value -c id

echo "5/5 Somme calculée par Glance (os_hash_value, sha512) contre celle du fichier envoyé…"
glance="$(openstack image show "$nom" -f json | jq -r '.os_hash_value')"
if [[ "$glance" != "$locale" ]]; then
  echo "DIVERGENCE : Glance $glance, fichier $locale. L'image est désactivée." >&2
  openstack image set --deactivate "$nom" || true
  exit 1
fi
echo "OK : $nom publiée, SHA-512 identique de la source à Glance."
