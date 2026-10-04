#!/usr/bin/env bash
# shellcheck disable=SC2016  # les motifs sed contiennent des $ littéraux (code Bash à écrire)
# fabriquer-situations.sh — prépare les situations à réparer de l'exercice M01-E08.
#
# Usage : fabriquer-situations.sh [DÉPÔT]      (défaut : $WB_SRC/git-labo, soit ~/src/git-labo)
#
# Prérequis : M01-E07 terminé — DÉPÔT est ton clone de formation/git-labo, avec un remote
# « origin » joignable en SSH et un arbre de travail propre.
#
# Ce que fait le script, à partir de origin/main :
#   - e08/publiee   : 3 commits « de Karim », PUBLIÉS sur origin (seule écriture distante) ;
#   - e08/brouillon : 3 commits de travail en cours, locaux ;
#   - e08/precieux  : 2 commits locaux, puis un « accident » (reset --hard) qui les fait disparaître ;
#   - e08/travail   : un commit local au message fautif et incomplet, puis des modifications
#                     en cours (dont une indexation malheureuse) ; c'est la branche active à la fin.
# Les commits fabriqués ne sont pas signés (le script n'a pas accès à ta phrase de passe) ;
# ceux que tu feras pendant l'exercice le seront, selon ta configuration de l'E03.
#
# Le script refuse de s'exécuter si une branche e08/* existe déjà, en local ou sur origin.
set -euo pipefail

depot="${1:-${WB_SRC:-$HOME/src}/git-labo}"

die() { echo "Refus : $*" >&2; exit 1; }

[[ -d "$depot" ]] || die "$depot n'existe pas (fais d'abord l'E07)."
cd "$depot"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$depot n'est pas un dépôt Git."
git remote get-url origin >/dev/null 2>&1 || die "pas de remote « origin » dans $depot (E07, étape 2)."
[[ -z "$(git status --porcelain)" ]] || die "l'arbre de travail de $depot n'est pas propre (git status)."
git config user.email >/dev/null || die "identité Git absente (E03)."

if git for-each-ref --format='%(refname)' 'refs/heads/e08/' | grep -q .; then
  die "des branches locales e08/* existent déjà. Supprime-les (git branch -D …) pour recommencer."
fi
git fetch -q origin
if git ls-remote --heads origin 'e08/*' | grep -q .; then
  die "des branches e08/* existent déjà sur origin. Supprime-les (git push origin --delete …) pour recommencer."
fi
git rev-parse -q --verify origin/main >/dev/null || die "origin/main introuvable."

# Commits non signés pour la fabrication uniquement
gitf() { git -c commit.gpgsign=false "$@"; }

# --- Situation « publiée » : commits de Karim, poussés --------------------------------------
gitf switch -q --no-track -c e08/publiee origin/main
karim() {
  GIT_AUTHOR_NAME="Karim Benali" GIT_AUTHOR_EMAIL="karim.benali@medisphere.internal" \
  GIT_COMMITTER_NAME="Karim Benali" GIT_COMMITTER_EMAIL="karim.benali@medisphere.internal" \
  gitf "$@"
}
cat > lib/rotation.sh <<'EOF'
# Rotation des exports : on garde les 7 derniers fichiers de chaque format.
tourner_exports() {
    ls -1t "$REPERTOIRE_EXPORT"/*."$1" 2>/dev/null | tail -n +8
}
EOF
git add lib/rotation.sh
karim commit -q -m "feat: rotation des exports"
cat >> conf/inventaire.conf <<'EOF'
PURGE_AUTO=oui
EOF
git add conf/inventaire.conf
karim commit -q -m "feat: activer la purge automatique des exports"
cat >> README.md <<'EOF'

## Rotation

Les 7 derniers exports de chaque format sont conservés (`lib/rotation.sh`).
EOF
git add README.md
karim commit -q -m "docs: documenter la rotation"
git push -q -u origin e08/publiee 2>/dev/null

# --- Situation « brouillon » : trois commits de travail en cours ----------------------------
gitf switch -q --no-track -c e08/brouillon origin/main
cat > exemples/exclusions.txt <<'EOF'
# VM à exclure de l'inventaire (une par ligne)
template-debain13
EOF
git add exemples/exclusions.txt
gitf commit -q -m "wip"
cat >> lib/format.sh <<'EOF'

lister_exclusions() {
    grep -v '^#' "$1"
}
EOF
git add lib/format.sh
gitf commit -q -m "wip 2"
sed -i 's/template-debain13/template-debian13/' exemples/exclusions.txt
git add exemples/exclusions.txt
gitf commit -q -m "correction faute"

# --- Situation « précieux » : deux commits, puis l'accident --------------------------------
gitf switch -q --no-track -c e08/precieux origin/main
mkdir -p notes
cat > notes/analyse-capacite.md <<'EOF'
# Analyse de capacité de l'inventaire

Mesures du 12 février : 1 200 VM inventoriées en 4 min 10 s.
EOF
git add notes/analyse-capacite.md
gitf commit -q -m "feat: travail précieux (1/2)"
cat >> notes/analyse-capacite.md <<'EOF'

Goulet d'étranglement : un appel à `stat` par VM. Piste : traitement par lots.
EOF
git add notes/analyse-capacite.md
gitf commit -q -m "feat: travail précieux (2/2)"
# L'accident : un reset --hard de trop sur la mauvaise branche
git reset -q --hard HEAD~2

# --- Situation « travail » : commit fautif, puis modifications en cours --------------------
gitf switch -q --no-track -c e08/travail origin/main
cat > conf/exclusions.conf <<'EOF'
# VM exclues de l'inventaire (noms exacts, une par ligne)
tpl-debian13
EOF
sed -i 's|^do$|do\n    grep -qxF "$nom" conf/exclusions.conf \&\& continue|' inventaire.sh
git add inventaire.sh            # conf/exclusions.conf est oublié volontairement
gitf commit -q -m "fix: corection du filtre d'exclusion"
printf '\nLIGNE AJOUTÉE PAR ERREUR\n' >> README.md
cat > secret.env <<'EOF'
# Jeton de l'API d'inventaire (fichier d'exercice : ce n'est pas un vrai secret)
INVENTAIRE_API_TOKEN=exercice-e08-pas-un-vrai-secret
EOF
git add secret.env

echo "Situations prêtes dans $depot (branche active : e08/travail)."
echo "Branches : e08/publiee (publiée), e08/brouillon, e08/precieux, e08/travail (locales)."
echo "Lis l'énoncé de l'E08 avant toute commande : certaines erreurs ne se rattrapent pas."
