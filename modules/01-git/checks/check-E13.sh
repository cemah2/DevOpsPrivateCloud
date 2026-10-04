# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes passées entre apostrophes à bash -c, évaluées plus tard
#
# check-E13.sh — M01-E13 : conflits de fusion et de rebase (formation/git-labo, e13/inventaire-runner01)
# Lancé depuis adm01. Lecture seule (configuration Git locale, clone $WB_SRC/git-labo, API GitLab).

title "M01-E13 — Résoudre des conflits de fusion et de rebase"
require_cmd curl jq git bash

_m01_p="projects/formation%2Fgit-labo"
_m01_b="e13%2Finventaire-runner01"
_m01_clone="${WB_SRC:-$HOME/src}/git-labo"

# --- Poste de travail -------------------------------------------------------------------------
check_output "Git : rerere activé dans ta configuration globale" '^true$' git config --global --get rerere.enabled
check_output "Git : style de conflit à trois versions (diff3 ou zdiff3)" '^z?diff3$' git config --global --get merge.conflictStyle
_m01_rr() {
  local d
  d="$(git -C "$_m01_clone" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  compgen -G "$d/rr-cache/*/postimage*" >/dev/null
}
check_cmd "rerere a enregistré au moins une résolution dans $_m01_clone" _m01_rr

# --- Branche publiée ------------------------------------------------------------------------------
_m01_main="$(gitlab_api "$_m01_p/repository/branches/main" 2>/dev/null | jq -r '.commit.id // empty')" || _m01_main=""
_m01_tip="$(gitlab_api "$_m01_p/repository/branches/$_m01_b" 2>/dev/null | jq -r '.commit.id // empty')" || _m01_tip=""
check_cmd "la branche e13/inventaire-runner01 existe sur formation/git-labo" test -n "$_m01_tip"

if [[ -n "$_m01_tip" && -n "$_m01_main" ]]; then
  _m01_mb="$(gitlab_api "$_m01_p/repository/merge_base?refs%5B%5D=main&refs%5B%5D=$_m01_b" 2>/dev/null \
    | jq -r '.id // empty')" || _m01_mb=""
  check_cmd "la branche est rebasée sur le dernier commit de main" test "$_m01_mb" = "$_m01_main"
  check_cmd "historique linéaire : aucun commit de fusion dans la branche" \
    test "$(gitlab_api "$_m01_p/repository/compare?from=main&to=$_m01_b" 2>/dev/null \
      | jq '[.commits[] | select((.parent_ids | length) > 1)] | length' 2>/dev/null || echo 1)" = 0

  _m01_inv="$(gitlab_api "$_m01_p/repository/files/conflits%2Finventaire.md/raw?ref=$_m01_tip" 2>/dev/null)" || _m01_inv=""
  _m01_sav="$(gitlab_api "$_m01_p/repository/files/conflits%2Fsauvegarde.sh/raw?ref=$_m01_tip" 2>/dev/null)" || _m01_sav=""
  check_cmd "aucun marqueur de conflit dans les fichiers de l'atelier" \
    bash -c '! grep -Eq "^(<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|\|)" <<<"$1"' _ "$_m01_inv$_m01_sav"
  check_cmd "inventaire : la ligne git01 de Karim est conservée" grep -q '^| git01 | 1004 |' <<<"$_m01_inv"
  check_cmd "inventaire : ta ligne runner01 est présente" grep -q '^| runner01 | 1007 |' <<<"$_m01_inv"
  check_cmd "inventaire : dns01 combine les deux modifications (2 Go, rôle précisé par Karim)" \
    grep -Eq "^\| dns01 \| 1002 \|.*\| 2 Go \|.*provisoire jusqu'au M06" <<<"$_m01_inv"
  check_cmd "sauvegarde.sh : syntaxe valide" bash -n <<<"$_m01_sav"
  check_cmd "sauvegarde.sh : ta vérification du stockage est conservée" grep -q 'verifier_stockage' <<<"$_m01_sav"
  check_cmd "sauvegarde.sh : plus aucune référence à l'ancienne variable DEST" \
    bash -c '! grep -Eq "\\\$\{?DEST\b|^DEST=" <<<"$1"' _ "$_m01_sav"
  check_cmd "une merge request est ouverte (ou fusionnée) depuis la branche" \
    test "$(gitlab_api "$_m01_p/merge_requests?source_branch=$_m01_b&state=all" 2>/dev/null \
      | jq '[.[] | select(.state == "opened" or .state == "merged")] | length' 2>/dev/null || echo 0)" -ge 1
else
  skip "contenu de la branche" "branche ou main introuvable"
fi
