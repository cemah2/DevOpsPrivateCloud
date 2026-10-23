#!/usr/bin/env bash
# outils/generer-index-runbooks.sh — plateforme/medisphere (F3-S01, PLAT-3301)
# Régénère la partie « Par domaine » de docs/exploitation/index-runbooks.md à partir des fichiers
# docs/**/runbooks/RB-NNN-*.md du dépôt (titre = premier titre de niveau 1 du runbook, sinon le nom).
# Usage (racine du clone) : outils/generer-index-runbooks.sh [--verifier]
#   --verifier : n'écrit rien, code 1 si l'index n'est pas à jour (job de CI).
set -euo pipefail

index=docs/exploitation/index-runbooks.md
debut='<!-- début de la partie générée : outils/generer-index-runbooks.sh -->'
fin='<!-- fin de la partie générée -->'
[[ -f "$index" ]] || { echo "index absent : $index" >&2; exit 2; }
if ! grep -qF -- "$debut" "$index" || ! grep -qF -- "$fin" "$index"; then
  echo "marqueurs de la partie générée absents de $index" >&2
  exit 2
fi

genere="$(mktemp)"
trap 'rm -f "$genere" "$genere.neuf"' EXIT

# Fichiers retenus : RB-NNN-<titre>.md ; les extraits et compléments de travail sont ignorés.
mapfile -t fichiers < <(find docs -path '*/runbooks/RB-[0-9][0-9][0-9]-*.md' ! -name '*extrait*' ! -name '*complement*' | LC_ALL=C sort)
dossier_prec=""
for f in "${fichiers[@]}"; do
  d="$(dirname "$f")"
  if [[ "$d" != "$dossier_prec" ]]; then
    printf '\n### %s\n\n| Runbook | Fichier |\n|---|---|\n' "${d#docs/}" >>"$genere"
    dossier_prec="$d"
  fi
  id="$(basename "$f" | cut -c1-6)"
  titre="$(sed -n 's/^# *//p' "$f" | head -n 1 | sed -E 's/^RB-[0-9]{3} *(—|:|-) *//')"
  [[ -n "$titre" ]] || titre="$(basename "$f" .md | cut -c8- | tr '-' ' ')"
  # Lien relatif depuis docs/exploitation/
  # shellcheck disable=SC2016  # accents graves littéraux (Markdown)
  printf '| **%s** — %s | [`%s`](../%s) |\n' "$id" "${titre//|/\\|}" "$f" "${f#docs/}" >>"$genere"
done

awk -v debut="$debut" -v fin="$fin" -v g="$genere" '
  $0 == debut { print; while ((getline l < g) > 0) print l; saute = 1; next }
  $0 == fin   { saute = 0 }
  !saute      { print }' "$index" >"$genere.neuf"

if [[ "${1:-}" == --verifier ]]; then
  if cmp -s "$index" "$genere.neuf"; then echo "index à jour (${#fichiers[@]} runbooks)"; exit 0; fi
  echo "index des runbooks pas à jour : lance outils/generer-index-runbooks.sh" >&2
  diff -u "$index" "$genere.neuf" | head -n 40 >&2 || true
  exit 1
fi
cp "$genere.neuf" "$index"
echo "index régénéré : ${#fichiers[@]} runbooks"
