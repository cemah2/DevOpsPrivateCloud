#!/usr/bin/env bash
# =============================================================================
# installer-release-tools.sh — installe /opt/release-tools sur un runner (M01-E24)
#
# Usage (sur runner01, en root, depuis un clone de plateforme/ci-templates) :
#   sudo outils/release-tools/installer-release-tools.sh
#
# Installe EXACTEMENT les versions de package-lock.json (npm ci), sans exécuter
# les scripts d'installation des paquets (--ignore-scripts), dans un dossier
# appartenant à root et en lecture seule pour l'utilisateur gitlab-runner :
# un job ne peut pas modifier les outils utilisés par les jobs suivants.
# Prérequis : Node.js 24 (dépôt NodeSource), npm 11.
# =============================================================================
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST=/opt/release-tools

[[ $EUID -eq 0 ]] || { echo "À lancer en root (sudo)." >&2; exit 1; }
command -v node >/dev/null || { echo "Node.js absent : installe Node.js 24 (NodeSource) d'abord." >&2; exit 1; }
majeure="$(node -p 'process.versions.node.split(".")[0]')"
((majeure >= 24)) || { echo "Node.js $majeure trop ancien : 24 LTS requis (semantic-release 25, commitlint 21)." >&2; exit 1; }

install -d -o root -g root -m 0755 "$DEST"
install -o root -g root -m 0644 "$ICI/package.json" "$ICI/package-lock.json" "$DEST/"

# Installation dans un dossier neuf puis bascule : jamais de node_modules à moitié installé
# pendant qu'un job tourne.
neuf="$DEST/node_modules.neuf"
rm -rf "$neuf" "$DEST/.npm-ci"
install -d -m 0755 "$DEST/.npm-ci"
cp "$DEST/package.json" "$DEST/package-lock.json" "$DEST/.npm-ci/"
(cd "$DEST/.npm-ci" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund)
mv "$DEST/.npm-ci/node_modules" "$neuf"
rm -rf "$DEST/.npm-ci"
if [[ -d "$DEST/node_modules" ]]; then
  mv "$DEST/node_modules" "$DEST/node_modules.ancien"
fi
mv "$neuf" "$DEST/node_modules"
rm -rf "$DEST/node_modules.ancien"
chown -R root:root "$DEST"
chmod -R go-w "$DEST"

echo "Outils installés :"
npm ls --prefix "$DEST" --depth=0
