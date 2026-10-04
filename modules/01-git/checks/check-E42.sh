# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent leurs paramètres en arguments
#
# check-E42.sh — M01-E42 « Panne : tout mon travail a disparu »
# Tout le travail de Lucas dans ~/src/labo-e42 est de nouveau atteignable : 4 commits sur
# feature/rotation-jetons, notes du stash, et le script indexé mais jamais commité s'il a
# existé. Lecture seule (git fsck sans --lost-found n'écrit rien).

# shellcheck source=_m01-palier4.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-palier4.sh"

title "M01-E42 — Panne : tout mon travail a disparu"
require_cmd git

_m01_d42="${WB_SRC:-$HOME/src}/labo-e42"

# Le contenu « Purge des jetons révoqués » n'existe que dans une variante : s'il traîne dans un
# objet orphelin sans être ni dans l'arbre de travail ni dans une référence, il est perdu.
_m01_e42_purge_ok() {
  local d="$1" motif="Purge des jetons révoqués" b
  grep -rqF "$motif" "$d/scripts" 2>/dev/null && return 0
  git -C "$d" log --all -p --diff-merges=first-parent 2>/dev/null | grep -qF "$motif" && return 0
  while read -r b; do
    git -C "$d" cat-file -p "$b" 2>/dev/null | grep -qF "$motif" && return 1
  done < <(git -C "$d" fsck --unreachable --no-reflogs 2>/dev/null | awk '$2 == "blob" {print $3}')
  return 0
}

if ! _m01_depot_absent_ok "$_m01_d42"; then
  check_cmd "labo-e42 : dépôt présent (sinon : lab/bin/break 01 42)" test -d "$_m01_d42/.git"
  check_cmd "labo-e42 : la branche feature/rotation-jetons existe" \
    git -C "$_m01_d42" rev-parse -q --verify refs/heads/feature/rotation-jetons
  check_cmd "labo-e42 : les 4 commits de Lucas sont sur feature/rotation-jetons" \
    _m01_sujets_presents "$_m01_d42" origin/main..feature/rotation-jetons \
    "feat(jetons): signaler les jetons qui expirent sous 30 jours" \
    "feat(jetons): renouveler un jeton de projet par l'API" \
    "docs(jetons): rappeler la mise à jour de la variable CI après rotation" \
    "feat(jetons): produire le rapport hebdomadaire des expirations"
  check_cmd "labo-e42 : les notes de conception du stash sont récupérées" \
    bash -c 'git -C "$1" log --all -p --diff-merges=first-parent 2>/dev/null | grep -qF "Conception retenue" \
             || grep -qF "Conception retenue" "$1/notes/idees.md"' _ "$_m01_d42"
  check_cmd "labo-e42 : aucun travail indexé laissé à l'abandon (objets orphelins)" _m01_e42_purge_ok "$_m01_d42"
  check_cmd "labo-e42 : intégrité (git fsck)" git -C "$_m01_d42" fsck
fi
