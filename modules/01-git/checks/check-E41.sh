# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent leurs paramètres en arguments
#
# check-E41.sh — M01-E41 « Panne : le dépôt local est corrompu »
# Le dépôt de Lucas (~/src/labo-e41, fabriqué par la panne) est intègre ET rien n'a été perdu :
# 3 commits de la branche, stash, modification en cours ; la branche est sécurisée sur l'origine.
# Lecture seule.

# shellcheck source=_m01-palier4.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-palier4.sh"

title "M01-E41 — Panne : le dépôt local est corrompu"
require_cmd git

_m01_d41="${WB_SRC:-$HOME/src}/labo-e41"
if ! _m01_depot_absent_ok "$_m01_d41"; then
  check_cmd "labo-e41 : dépôt présent (sinon : lab/bin/break 01 41)" test -d "$_m01_d41/.git"
  check_cmd "labo-e41 : Git reconnaît le dépôt et lit l'index (git status)" git -C "$_m01_d41" status --porcelain
  check_cmd "labo-e41 : intégrité complète (git fsck --full sans erreur)" git -C "$_m01_d41" fsck --full
  check_output "labo-e41 : branche courante feature/sauvegarde-gitlab" '^feature/sauvegarde-gitlab$' \
    git -C "$_m01_d41" symbolic-ref --short HEAD
  check_cmd "labo-e41 : les 3 commits non publiés sont sur la branche" \
    _m01_sujets_presents "$_m01_d41" origin/main..feature/sauvegarde-gitlab \
    "feat(sauvegarde): ajouter le script de sauvegarde de GitLab" \
    "feat(sauvegarde): copier la sauvegarde vers PBS" \
    "docs(runbook): détailler la restauration de gitlab-secrets.json"
  check_output "labo-e41 : le stash « essai option --dry-run » est conservé" 'essai option --dry-run' \
    git -C "$_m01_d41" stash list
  check_cmd "labo-e41 : la modification en cours du runbook est conservée" \
    grep -q 'gitlab:doctor:secrets' "$_m01_d41/docs/RB-010-restaurer-gitlab.md"
  check_cmd "labo-e41 : la branche est publiée sur l'origine, à jour" bash -c '
    l=$(git -C "$1" rev-parse -q --verify refs/heads/feature/sauvegarde-gitlab) &&
    o=$(git -C "$1-origine.git" rev-parse -q --verify refs/heads/feature/sauvegarde-gitlab) &&
    [ "$l" = "$o" ]' _ "$_m01_d41"
fi
