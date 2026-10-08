#!/usr/bin/env bash
# recreer-images.sh — recrée une image Glance au format raw depuis sa source officielle,
# après vérification de la somme publiée (M10-E10).
# Usage : outils/recreer-images.sh <nom> <url-image> <url-sommes> <propriétés…>
#   ex. : outils/recreer-images.sh debian-13 \
#           https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2 \
#           https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS \
#           os_distro=debian os_version=13 hw_disk_bus=scsi hw_scsi_model=virtio-scsi hw_qemu_guest_agent=yes
# Prérequis : qemu-utils, cloud OS_CLOUD (ex. medisphere-admin), ~15 Go libres dans $TMPDIR.
set -euo pipefail

[[ $# -ge 3 ]] || { sed -n '3,9p' "$0" >&2; exit 2; }
nom="$1"; url="$2"; url_sommes="$3"; shift 3
: "${OS_CLOUD:?définis OS_CLOUD (ex. medisphere-admin)}"

travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT
fichier="$travail/$(basename "$url")"

curl -fsSL -o "$fichier" "$url"
curl -fsSL -o "$travail/sommes" "$url_sommes"
attendu="$(awk -v f="$(basename "$url")" '$2 == f || $2 == "*"f {print $1}' "$travail/sommes")"
[[ -n "$attendu" ]] || { echo "somme introuvable pour $(basename "$url")" >&2; exit 1; }
case "${#attendu}" in
  128) outil=sha512sum ;;
  64) outil=sha256sum ;;
  *) echo "format de somme inconnu" >&2; exit 1 ;;
esac
echo "$attendu  $fichier" | "$outil" -c --quiet
echo "somme vérifiée ($outil)"

format="$(qemu-img info --output=json "$fichier" | jq -r .format)"
brut="$travail/$nom.raw"
if [[ "$format" == "raw" ]]; then
  mv "$fichier" "$brut"
else
  qemu-img convert -p -f "$format" -O raw "$fichier" "$brut"
  rm -f "$fichier"
fi

proprietes=()
for p in "$@"; do proprietes+=(--property "$p"); done

openstack image create --disk-format raw --container-format bare --public \
  --property "source_url=$url" --property "source_sha=$attendu" \
  "${proprietes[@]}" --file "$brut" --progress "$nom"
openstack image show -c status -c disk_format -c stores -c direct_url "$nom"
