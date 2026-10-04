#!/usr/bin/env bash
# solution-e08.sh — résolution des six situations de M01-E08, dans l'ordre de l'énoncé.
# Usage : solution-e08.sh [DÉPÔT]   (juste après fabriquer-situations.sh, branche e08/travail)
# Script de démonstration : dans la vraie vie, on regarde « git status » entre chaque étape.
set -euo pipefail

cd "${1:-${WB_SRC:-$HOME/src}/git-labo}"
[[ "$(git branch --show-current)" == "e08/travail" ]] || { echo "Attendu : branche e08/travail." >&2; exit 1; }

# Situation 1 — modification non indexée à jeter : index -> arbre de travail, pour CE fichier
git restore README.md

# Situation 2 — désindexer sans supprimer, puis empêcher la récidive pour toute l'équipe
git restore --staged secret.env                  # HEAD -> index ; le fichier reste sur le disque
printf '# Secrets locaux : jamais dans le dépôt\nsecret.env\n' >> .gitignore
git add .gitignore
git commit -m "chore: ignorer secret.env"
chore="$(git rev-parse HEAD)"

# Situation 3 — corriger l'avant-dernier commit (non publié) sans rebase interactif :
# retirer le commit chore (--keep : garde les fichiers non suivis et refuse d'écraser
# une modification locale), amender, puis réappliquer le commit chore.
git reset --keep HEAD~1
git add conf/exclusions.conf
git commit --amend -m "fix: correction du filtre d'exclusion"
git cherry-pick "$chore"
git push -u origin e08/travail

# Situation 4 — trois commits locaux en un seul, même contenu final
git switch e08/brouillon
base="$(git merge-base e08/brouillon origin/main)"
git reset --soft "$base"                         # la branche recule ; index et fichiers intacts
git commit -m "feat: liste d'exclusion de l'inventaire"
git push -u origin e08/brouillon

# Situation 5 — annuler un commit publié sans réécrire : un commit inverse
git switch e08/publiee
fautif="$(git log --format=%H --grep='^feat: activer la purge automatique des exports$' -n 1)"
git revert --no-edit "$fautif"
git push

# Situation 6 — retrouver la position de la branche avant l'accident dans son reflog
git switch e08/precieux
git reflog show e08/precieux                     # @{0} = reset, @{1} = dernier commit précieux
git reset --hard 'e08/precieux@{1}'              # arbre propre vérifié par « git switch »
git push -u origin e08/precieux

git log --oneline --graph -n 4 e08/travail e08/brouillon e08/publiee e08/precieux
ls -l secret.env
