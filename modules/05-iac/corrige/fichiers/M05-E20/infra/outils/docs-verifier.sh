#!/usr/bin/env bash
# docs-verifier.sh — la documentation générée (terraform-docs) est à jour (M05-E20).
#
# Pour chaque configuration dont le README.md contient les marqueurs BEGIN_TF_DOCS /
# END_TF_DOCS, vérifie que le tableau correspond au code (variables, sorties, ressources).
# Si non : lance « terraform-docs <dossier> » depuis la racine, relis, commite.
set -euo pipefail

racine="$(git rev-parse --show-toplevel)"
cd "$racine"
echec=0
while IFS= read -r readme; do
  dossier="$(dirname "$readme")"
  if ! terraform-docs --output-check "$dossier" >/dev/null 2>&1; then
    printf 'documentation périmée : %s (lance : terraform-docs %s)\n' "$readme" "$dossier" >&2
    echec=1
  fi
done < <(grep -rl --include=README.md 'BEGIN_TF_DOCS' . | grep -v '/\.terraform/' | sort)
exit "$echec"
