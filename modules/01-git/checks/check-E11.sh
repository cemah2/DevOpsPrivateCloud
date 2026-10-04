# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes passées entre apostrophes à bash -c, évaluées plus tard
#
# check-E11.sh — M01-E11 : protéger main de plateforme/medisphere et outiller les futurs projets
# Lancé depuis adm01. Lecture seule (API GitLab avec le jeton des checks, fichiers locaux).

title "M01-E11 — Protéger main : branches protégées et règles de fusion"
require_cmd curl jq

_m01_p="projects/plateforme%2Fmedisphere"
_m01_jq() { jq -e "$1" <<<"$2" >/dev/null 2>&1; }

# --- Branche protégée ---------------------------------------------------------------------
_m01_pb="$(gitlab_api "$_m01_p/protected_branches/main" 2>/dev/null)" || _m01_pb=""
check_cmd "main est une branche protégée" test -n "$_m01_pb"
check_cmd "main : personne ne peut pousser directement (push « No one »)" \
  _m01_jq '(.push_access_levels | length) > 0 and all(.push_access_levels[]; .access_level == 0)' "$_m01_pb"
check_cmd "main : seuls les Maintainers peuvent fusionner" \
  _m01_jq 'any(.merge_access_levels[]; .access_level == 40) and all(.merge_access_levels[]; .access_level >= 40)' "$_m01_pb"
check_cmd "main : le push forcé est interdit" _m01_jq '.allow_force_push == false' "$_m01_pb"

# --- Réglages des merge requests du projet ----------------------------------------------------
_m01_proj="$(gitlab_api "$_m01_p" 2>/dev/null)" || _m01_proj="{}"
check_cmd "fusion impossible tant qu'un fil de discussion est ouvert" \
  _m01_jq '.only_allow_merge_if_all_discussions_are_resolved == true' "$_m01_proj"
check_cmd "méthode de fusion : commit de fusion avec historique semi-linéaire (décision de l'équipe)" \
  _m01_jq '.merge_method == "rebase_merge"' "$_m01_proj"
check_cmd "message des suggestions appliquées conforme à Conventional Commits" \
  _m01_jq '(.suggestion_commit_message // "") | test("^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\\([^)]+\\))?: ")' "$_m01_proj"
if _m01_jq '.squash_option == "always" or .squash_option == "default_on"' "$_m01_proj"; then
  check_cmd "squash encouragé ou imposé : le modèle de message de squash est personnalisé" \
    _m01_jq '(.squash_commit_template // "") != ""' "$_m01_proj"
else
  skip "modèle de message de squash" "squash non encouragé"
fi

# --- Script réutilisable pour les futurs projets plateforme/* -----------------------------------
_m01_script="$HOME/lab-scripts/gitlab-proteger-projet.sh"
check_cmd "gitlab-proteger-projet.sh présent et exécutable dans ton dossier lab-scripts" test -x "$_m01_script"
if command -v shellcheck >/dev/null 2>&1; then
  check_cmd "gitlab-proteger-projet.sh passe shellcheck" shellcheck -x "$_m01_script"
else
  skip "gitlab-proteger-projet.sh passe shellcheck" "shellcheck absent"
fi
check_cmd "gitlab-proteger-projet.sh ne contient pas de jeton en clair" \
  bash -c '! grep -Eq "glpat-[0-9A-Za-z_.-]{20}" "$1"' _ "$_m01_script"
