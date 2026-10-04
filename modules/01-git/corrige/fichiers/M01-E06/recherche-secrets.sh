#!/usr/bin/env bash
# recherche-secrets.sh — recherche grossière de secrets et de gros objets dans TOUT l'historique
# d'un dépôt, avant publication (M01-E06). Ne remplace pas Gitleaks (M01-E16).
# Usage : recherche-secrets.sh [DÉPÔT]       Code retour 1 si un motif suspect est trouvé.
set -euo pipefail

depot="${1:-${WB_DEPOT:-$HOME/medisphere}}"
cd "$depot"
suspect=0

echo "== Motifs de secrets dans toutes les modifications de tous les commits =="
# Lignes ajoutées (+) uniquement : clés privées, clés WireGuard, affectations de secrets
motif='BEGIN [A-Z ]*PRIVATE KEY|PrivateKey *= *[A-Za-z0-9+/]{42,43}=|(token|password|passwd|secret|api[_-]?key)[A-Za-z0-9_]* *[:=] *[^ <$]{8,}'
if git log --all -p --no-color --format='commit %H' | grep -nEi "^\+.*($motif)"; then
  suspect=1
  echo ">> Motifs suspects ci-dessus : examine chaque ligne (git log --all -S'<extrait>')."
else
  echo "aucun motif suspect"
fi

echo "== Objets de plus de 1 Mo =="
git rev-list --objects --all \
  | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
  | awk '$1 == "blob" && $3 > 1048576 {print; n++} END {if (!n) print "aucun"}'

exit "$suspect"
