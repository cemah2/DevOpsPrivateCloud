# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E39.sh — M01-E39 « Panne : la release automatique échoue »
# Chaîne de release de plateforme/medisphere : jeton du bot, variable CI, protection des
# étiquettes, outils sur runner01, dernier pipeline de main et cohérence étiquette/Release.
# Lecture seule (la valeur du jeton n'est jamais lue).

# shellcheck source=_m01-palier4.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-palier4.sh"

title "M01-E39 — Panne : la release automatique échoue"
require_cmd jq curl

check_cmd "jeton de projet bot-release : un seul actif, Maintainer, portées api et write_repository" \
  _m01_api_ok "$_M01_P_MED/access_tokens?state=active&per_page=100" \
  '[.[] | select(.name == "bot-release" and .active)] | length == 1 and (.[0].access_level == 40)
     and (.[0].scopes | index("api") and index("write_repository"))'
check_cmd "jeton bot-release : déjà utilisé (la CI dispose bien du jeton actif)" \
  _m01_api_ok "$_M01_P_MED/access_tokens?state=active&per_page=100" \
  '[.[] | select(.name == "bot-release" and .active)] | .[0].last_used_at != null'
if _m01_api_existe "$_M01_P_MED/variables/GITLAB_TOKEN"; then
  check_cmd "variable CI GITLAB_TOKEN : protégée, masquée, valable pour tous les environnements" \
    _m01_api_ok "$_M01_P_MED/variables/GITLAB_TOKEN" '.protected and .masked and .environment_scope == "*"'
else
  skip "variable CI GITLAB_TOKEN du projet" "définie au niveau du groupe ou absente"
fi
check_cmd "étiquettes v* protégées, création réservée aux Maintainers" \
  _m01_api_ok "$_M01_P_MED/protected_tags/v%2A" '[.create_access_levels[].access_level] | max == 40'
check_ssh "runner01 : plugin @semantic-release/gitlab présent dans /opt/release-tools" runner01 \
  'test -f /opt/release-tools/node_modules/@semantic-release/gitlab/package.json'

_m01_pipe="$(gitlab_api "$_M01_P_MED/pipelines?ref=main&per_page=1" 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null)" || _m01_pipe=""
check_cmd "dernier pipeline de main : réussi" \
  _m01_api_ok "$_M01_P_MED/pipelines?ref=main&per_page=1" '.[0].status == "success"'
if [[ -n "$_m01_pipe" ]]; then
  check_cmd "dernier pipeline de main : job release réussi" \
    _m01_api_ok "$_M01_P_MED/pipelines/$_m01_pipe/jobs?per_page=100" \
    'any(.[]; .name == "release" and .status == "success")'
else
  skip "job release du dernier pipeline de main" "aucun pipeline sur main"
fi

_m01_e39_release_coherente() {
  local tag rel
  tag="$(gitlab_api "$_M01_P_MED/repository/tags?order_by=version&search=%5Ev&per_page=1" | jq -r '.[0].name // empty')" || return 1
  rel="$(gitlab_api "$_M01_P_MED/releases?per_page=1" | jq -r '.[0].tag_name // empty')" || return 1
  [[ -n "$tag" && "$tag" == "$rel" ]]
}
check_cmd "la plus récente étiquette v* a sa Release GitLab" _m01_e39_release_coherente
