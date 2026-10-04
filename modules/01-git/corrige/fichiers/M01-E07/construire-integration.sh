#!/usr/bin/env bash
# construire-integration.sh — solution des étapes 4 et 5 de M01-E07, dans ~/src/git-labo.
# Usage : construire-integration.sh [DÉPÔT]   (arbre propre, remote origin configuré)
set -euo pipefail

cd "${1:-${WB_SRC:-$HOME/src}/git-labo}"
[[ -z "$(git status --porcelain)" ]] || { echo "Arbre de travail non propre." >&2; exit 1; }

# Étape 4 : le commit qui a INTRODUIT SEUIL_ALERTE (recherche « pioche »), le plus ancien
seuil="$(git log -S SEUIL_ALERTE --format=%H --reverse main | head -n 1)"
git log -1 --format='%h %an %ad %s' --date=short "$seuil"
git tag e07/seuil "$seuil"                       # étiquette LÉGÈRE : pas de -a ni -m
git push origin e07/seuil

# Étape 5 : deux branches parties du même commit de main
git switch -c e07/ajout-pbs main
printf '\n## Sauvegarde\n\nLes exports sont sauvegardés sur pbs01 (PAR2).\n' >> README.md
git commit -am "docs: mentionner la sauvegarde des exports sur PBS"

git switch -c e07/ajout-dns main
mkdir -p docs
printf '# DNS\n\nLes noms des VM sont résolus par dns01 (10.10.20.10).\n' > docs/dns.md
git add docs/dns.md
git commit -m "docs: ajouter une note sur la résolution DNS"

git switch -c e07/integration main
git merge --ff-only e07/ajout-pbs                # avance rapide exigée : échoue plutôt que fusionner
git merge --no-ff --no-edit e07/ajout-dns        # commit de fusion imposé, message par défaut

git push -u origin e07/ajout-pbs e07/ajout-dns e07/integration
git log --oneline --graph -n 5 e07/integration
