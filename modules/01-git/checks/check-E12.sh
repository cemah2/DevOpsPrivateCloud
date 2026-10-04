# shellcheck shell=bash
#
# check-E12.sh — M01-E12 : rebase interactif de e12/verif-sauvegardes (formation/git-labo)
# Lancé depuis adm01. Lecture seule (API GitLab avec le jeton des checks ; bash -n sur des copies temporaires).

title "M01-E12 — Rebase interactif : préparer une branche pour la revue"
require_cmd curl jq bash

_m01_p="projects/formation%2Fgit-labo"
_m01_b="e12%2Fverif-sauvegardes"
_m01_f="rebase%2Fverif-pbs.sh"
_m01_cc='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9._/-]+\))?!?: [^A-Z]'

# _m01_titres_conformes JSON — tous les titres de .commits suivent Conventional Commits
_m01_titres_conformes() {
  local t
  while IFS= read -r t; do
    [[ "$t" =~ $_m01_cc ]] || return 1
  done < <(jq -r '.commits[].title' <<<"$1")
}
# _m01_aucun_brouillon JSON — aucun titre fixup!/squash!/amend!/wip
_m01_aucun_brouillon() {
  ! jq -r '.commits[].title' <<<"$1" | grep -Eiq '^(fixup!|squash!|amend!)|(^|[^a-z])wip([^a-z]|$)'
}
# _m01_chaque_commit JSON — à chaque commit, verif-pbs.sh (s'il existe) est valide et sans débogage
_m01_chaque_commit() {
  local sha contenu
  while IFS= read -r sha; do
    contenu="$(gitlab_api "$_m01_p/repository/files/$_m01_f/raw?ref=$sha" 2>/dev/null)" || continue
    bash -n <<<"$contenu" 2>/dev/null || return 1
    if grep -Eq '^[[:space:]]*set -x|DEBUG' <<<"$contenu"; then return 1; fi
  done < <(jq -r '.commits[].id' <<<"$1")
}

_m01_main="$(gitlab_api "$_m01_p/repository/branches/main" 2>/dev/null | jq -r '.commit.id // empty')" || _m01_main=""
_m01_tip="$(gitlab_api "$_m01_p/repository/branches/$_m01_b" 2>/dev/null | jq -r '.commit.id // empty')" || _m01_tip=""
check_cmd "la branche e12/verif-sauvegardes existe sur formation/git-labo" test -n "$_m01_tip"

if [[ -n "$_m01_tip" && -n "$_m01_main" ]]; then
  _m01_mb="$(gitlab_api "$_m01_p/repository/merge_base?refs%5B%5D=main&refs%5B%5D=$_m01_b" 2>/dev/null \
    | jq -r '.id // empty')" || _m01_mb=""
  check_cmd "la branche part du dernier commit de main (rebasée)" test "$_m01_mb" = "$_m01_main"

  _m01_cmp="$(gitlab_api "$_m01_p/repository/compare?from=main&to=$_m01_b" 2>/dev/null)" || _m01_cmp='{"commits":[]}'
  _m01_n="$(jq '.commits | length' <<<"$_m01_cmp" 2>/dev/null)" || _m01_n=0
  check_cmd "historique resserré : $_m01_n commit(s) au-dessus de main (attendu : 2, au plus 3)" \
    test "$_m01_n" -ge 1 -a "$_m01_n" -le 3
  check_cmd "chaque message suit Conventional Commits (type, sujet commençant par une minuscule)" \
    _m01_titres_conformes "$_m01_cmp"
  check_cmd "aucun commit de brouillon (wip, fixup!, squash!) ne subsiste" _m01_aucun_brouillon "$_m01_cmp"
  check_cmd "à chaque commit, verif-pbs.sh est syntaxiquement valide et sans trace de débogage" \
    _m01_chaque_commit "$_m01_cmp"

  _m01_fin="$(gitlab_api "$_m01_p/repository/files/$_m01_f/raw?ref=$_m01_tip" 2>/dev/null)" || _m01_fin=""
  check_cmd "version finale : l'option --datastore est conservée, avec ds-lab par défaut" \
    grep -q 'DATASTORE="ds-lab"' <<<"$_m01_fin"
  check_cmd "version finale : le mode d'emploi rebase/verif-pbs.md est présent" \
    test -n "$(gitlab_api "$_m01_p/repository/files/rebase%2Fverif-pbs.md/raw?ref=$_m01_tip" 2>/dev/null || true)"
  check_cmd "une merge request est ouverte (ou fusionnée) depuis la branche" \
    test "$(gitlab_api "$_m01_p/merge_requests?source_branch=$_m01_b&state=all" 2>/dev/null \
      | jq '[.[] | select(.state == "opened" or .state == "merged")] | length' 2>/dev/null || echo 0)" -ge 1
else
  skip "rebase, historique et contenu de la branche" "branche ou main introuvable"
fi
