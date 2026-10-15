#!/usr/bin/env bash
# outils/installer-velero-cli.sh — CLI velero sur adm01, empreinte vérifiée (M16-E16).
#   outils/installer-velero-cli.sh            # version figée ci-dessous
# L'empreinte vient du fichier CHECKSUM publié avec la version ; elle est AUSSI figée ici
# (relue en MR) : si le fichier publié change un jour, l'installation s'arrête.
set -euo pipefail
VERSION="v1.18.4"
ARCHIVE="velero-${VERSION}-linux-amd64.tar.gz"
EMPREINTE="e520c17d8997e1c9d0a28ae013592e4473ca3bd82cb3acd132e51286263f74bf"
BASE="https://github.com/vmware-tanzu/velero/releases/download/${VERSION}"

travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT
cd "$travail"
curl -fsSLO "$BASE/$ARCHIVE"
curl -fsSLO "$BASE/CHECKSUM"
grep -q "^${EMPREINTE}  ${ARCHIVE}\$" CHECKSUM || { echo "CHECKSUM publié différent de l'empreinte figée" >&2; exit 1; }
echo "${EMPREINTE}  ${ARCHIVE}" | sha256sum -c -
tar -xzf "$ARCHIVE"
sudo install -m 0755 "velero-${VERSION}-linux-amd64/velero" /usr/local/bin/velero
velero version --client-only
