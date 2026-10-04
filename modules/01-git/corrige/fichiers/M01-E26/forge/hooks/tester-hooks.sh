#!/usr/bin/env bash
# =============================================================================
# tester-hooks.sh — tests hors ligne des hooks pre-receive de la forge (M01-E26)
#
# Usage : forge/hooks/tester-hooks.sh [RÉPERTOIRE-DES-HOOKS]
#   RÉPERTOIRE-DES-HOOKS : dossier contenant les scripts (défaut : pre-receive.d/
#   à côté de ce script). Sur git01 : /var/opt/gitlab/gitaly/custom_hooks/pre-receive.d
#
# Principe : un dépôt nu « serveur » joue le rôle du dépôt GitLab ; les nouveaux
# commits sont créés dans un dépôt « travail » et rendus visibles au serveur par
# GIT_ALTERNATE_OBJECT_DIRECTORIES, comme le fait la quarantaine de Gitaly : les
# objets existent, mais aucune référence du serveur ne pointe encore dessus.
# Chaque hook reçoit la même entrée standard ; la chaîne s'arrête au premier échec.
#
# Aucun accès réseau, aucune modification hors d'un répertoire temporaire.
# Code retour : 0 si tous les scénarios donnent le résultat attendu.
# =============================================================================
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="${1:-$ICI/pre-receive.d}"
[[ -d "$HOOKS" ]] || { echo "Répertoire de hooks introuvable : $HOOKS" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export GIT_AUTHOR_NAME="Test Hooks" GIT_AUTHOR_EMAIL="test@medisphere.internal"
export GIT_COMMITTER_NAME="Test Hooks" GIT_COMMITTER_EMAIL="test@medisphere.internal"
export GIT_CONFIG_NOSYSTEM=1 HOME="$TMP"   # aucune configuration personnelle (signature, hooks…)

git init -q --bare -b main "$TMP/serveur.git"
git init -q -b main "$TMP/travail"
cd "$TMP/travail"
echo "socle" > README.md
git add README.md
git commit -q -m "chore: initialise le dépôt"
git push -q "$TMP/serveur.git" main
BASE="$(git rev-parse HEAD)"

# nouveau_commit MESSAGE [FICHIER TAILLE_OCTETS] — commit sur une branche jetable, affiche son SHA
nouveau_commit() {
  git checkout -q --detach "$BASE"
  if [[ $# -ge 3 ]]; then
    head -c "$3" /dev/urandom > "$2"
    git add "$2"
  else
    date +%s%N >> journal.txt
    git add journal.txt
  fi
  git commit -q -m "$1"
  git rev-parse HEAD
}

# lancer_chaine PROJET "ancien nouveau ref" [OPTION_DE_PUSH] — exécute les hooks comme Gitaly
lancer_chaine() {
  local projet="$1" ligne="$2" option="${3:-}" h rc=0
  local env_push=(GIT_PUSH_OPTION_COUNT=0)
  [[ -n "$option" ]] && env_push=(GIT_PUSH_OPTION_COUNT=1 "GIT_PUSH_OPTION_0=$option")
  for h in "$HOOKS"/*; do
    [[ -f "$h" && -x "$h" && "$h" != *~ ]] || continue
    (cd "$TMP/serveur.git" && env GIT_DIR="$TMP/serveur.git" \
        GIT_ALTERNATE_OBJECT_DIRECTORIES="$TMP/travail/.git/objects" \
        GL_PROJECT_PATH="$projet" GL_USERNAME=testeur GL_PROTOCOL=ssh GL_ID=user-1 \
        GL_REPOSITORY=project-1 "${env_push[@]}" "$h" <<<"$ligne") >"$TMP/sortie" 2>&1 || rc=$?
    ((rc == 0)) || break
  done
  return "$rc"
}

echecs=0
# verifier LIBELLÉ ATTENDU(accepte|refuse) PROJET LIGNE [OPTION]
verifier() {
  local libelle="$1" attendu="$2" obtenu
  shift 2
  if lancer_chaine "$@"; then obtenu=accepte; else obtenu=refuse; fi
  if [[ "$obtenu" == "$attendu" ]] && { [[ "$obtenu" == accepte ]] || grep -q '^GL-HOOK-ERR:' "$TMP/sortie"; }; then
    printf '[OK]  %s\n' "$libelle"
  else
    printf '[KO]  %s (attendu : %s, obtenu : %s)\n' "$libelle" "$attendu" "$obtenu"
    sed 's/^/      | /' "$TMP/sortie"
    echecs=$((echecs + 1))
  fi
}

ZERO=0000000000000000000000000000000000000000
P=plateforme/medisphere
F=formation/git-labo

c=$(nouveau_commit "feat(socle): ajoute l'inventaire de git01")
verifier "message conforme accepté" accepte "$P" "$BASE $c refs/heads/feat/inventaire"
c=$(nouveau_commit "Ajoute l'inventaire")
verifier "message non conforme refusé (plateforme)" refuse "$P" "$BASE $c refs/heads/feat/inventaire"
verifier "même commit accepté hors périmètre (formation)" accepte "$F" "$BASE $c refs/heads/essai"
verifier "nouvelle branche sur un commit déjà connu : rien à contrôler" accepte "$P" "$ZERO $BASE refs/heads/copie"
c=$(nouveau_commit "feat: $(printf 'x%.0s' {1..110})")
verifier "en-tête de plus de 100 caractères refusé" refuse "$P" "$BASE $c refs/heads/long"
c=$(nouveau_commit "fixup! feat(socle): ajoute l'inventaire de git01")
verifier "commit fixup! accepté (comme commitlint)" accepte "$P" "$BASE $c refs/heads/feat/inventaire"
c=$(nouveau_commit "Merge branch 'feat/inventaire' into 'main'")
verifier "commit de fusion GitLab accepté" accepte "$P" "$BASE $c refs/heads/main"
c=$(nouveau_commit "Revert \"feat(socle): ajoute l'inventaire de git01\"")
verifier "retour arrière généré par GitLab accepté" accepte "$P" "$BASE $c refs/heads/main"
verifier "suppression de branche acceptée" accepte "$P" "$BASE $ZERO refs/heads/feat/inventaire"
c=$(nouveau_commit "Ajoute l'inventaire")
verifier "dérogation d'un utilisateur non autorisé refusée" refuse "$P" "$BASE $c refs/heads/x" "derogation=CHG-999"

c=$(nouveau_commit "chore: ajoute une petite image" petit.bin $((4 * 1024 * 1024)))
verifier "fichier de 4 Mio accepté" accepte "$P" "$BASE $c refs/heads/img"
c=$(nouveau_commit "chore: ajoute une grosse image" gros.bin $((6 * 1024 * 1024)))
verifier "fichier de 6 Mio refusé" refuse "$P" "$BASE $c refs/heads/img"
git rm -q gros.bin
git commit -q -m "chore: retire la grosse image"
c2=$(git rev-parse HEAD)
verifier "gros fichier ajouté puis retiré : toujours refusé" refuse "$P" "$BASE $c2 refs/heads/img"
verifier "gros fichier accepté hors périmètre" accepte "$F" "$BASE $c2 refs/heads/img"

echo
if ((echecs == 0)); then
  echo "Tous les scénarios sont conformes."
else
  echo "$echecs scénario(s) en échec."
  exit 1
fi
