#!/usr/bin/env bash
# k3s/outils/kine-lire.sh — lecture de la base SQLite de kine sur une COPIE cohérente (M18-E23).
# Usage (depuis adm01) : k3s/outils/kine-lire.sh [HÔTE] [PRÉFIXE-DE-CLÉ]
#   défaut : k3s01, /registry/configmaps/wb-essais/
# Copie par « sqlite3 .backup » (cohérente même pendant les écritures de kine) dans un dossier 700 de
# root, requêtes en lecture sur la copie, effacement de la copie. N'affiche JAMAIS les valeurs (seulement
# les tailles) : la base contient des Secrets. Exige sqlite3 sur l'hôte (apt-get install sqlite3).
set -euo pipefail

hote="${1:-k3s01}"
prefixe="${2:-/registry/configmaps/wb-essais/}"

# shellcheck disable=SC2029  # le préfixe est passé volontairement, cité par printf %q
ssh "$hote" "sudo -n bash -s -- $(printf '%q' "$prefixe")" <<'DISTANT'
set -euo pipefail
prefixe="$1"
base=/var/lib/rancher/k3s/server/db/state.db
command -v sqlite3 >/dev/null || { echo "sqlite3 absent : apt-get install sqlite3" >&2; exit 1; }
d="$(mktemp -d /root/kine.XXXXXX)"; chmod 700 "$d"
trap 'rm -rf "$d"' EXIT
sqlite3 "$base" ".backup '$d/copie.db'"
echo "== Schéma de la table kine"
sqlite3 "$d/copie.db" ".schema kine"
echo "== Lignes et révision courante"
sqlite3 "$d/copie.db" "SELECT count(*) AS lignes, max(id) AS revision FROM kine;"
echo "== Compactage"
sqlite3 -header "$d/copie.db" "SELECT id, name, prev_revision FROM kine WHERE name = 'compact_rev_key' ORDER BY id DESC LIMIT 1;"
echo "== Vie des clés sous $prefixe (sans les valeurs)"
sqlite3 -header -column "$d/copie.db" \
  "SELECT id, name, created, deleted, create_revision, prev_revision, length(value) AS taille
     FROM kine WHERE name LIKE '${prefixe//\'/\'\'}%' ORDER BY name, id;"
DISTANT
