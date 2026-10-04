# shellcheck shell=bash
#
# check-E25.sh — M01-E25 « semantic-release : versions, changelog et releases automatiques »
# Lancé depuis adm01. Lecture seule (API GitLab). Les valeurs des variables CI ne
# sont jamais affichées : seuls leurs attributs (protégée, masquée) sont lus.

title "M01-E25 — semantic-release : versions et releases automatiques"
require_cmd jq curl

_m01_get() { gitlab_api "$1" 2>/dev/null || true; }
_m01_CT="plateforme%2Fci-templates"
_m01_MS="plateforme%2Fmedisphere"

# --- 1. Gabarit de release ----------------------------------------------------------------
_m01_rel="$(_m01_get "projects/$_m01_CT/repository/files/templates%2Frelease.yml/raw?ref=main")"
check_cmd "plateforme/ci-templates : templates/release.yml présent sur main" test -n "$_m01_rel"
check_cmd "templates/release.yml : job release qui lance semantic-release" \
  bash -c 'grep -Eq "^release:" <<<"$1" && grep -q "semantic-release" <<<"$1"' _ "$_m01_rel"

# --- 2. Par projet publié -------------------------------------------------------------------
for _m01_p in "$_m01_CT" "$_m01_MS"; do
  _m01_nom="${_m01_p//%2F//}"
  _m01_rc="$(_m01_get "projects/$_m01_p/repository/files/.releaserc.json/raw?ref=main")"
  check_cmd "$_m01_nom : .releaserc.json valide sur main" jq -e '.plugins | length > 0' <<<"$_m01_rc"
  check_cmd "$_m01_nom : preset conventionalcommits et extension @semantic-release/gitlab" \
    jq -e '[.plugins[] | if type == "array" then .[0] else . end] as $n | ($n | index("@semantic-release/gitlab")) and (tostring | test("conventionalcommits"))' <<<"$_m01_rc"
  check_cmd "$_m01_nom : aucune écriture dans main (ni @semantic-release/git, ni changelog)" \
    jq -e '[.plugins[] | if type == "array" then .[0] else . end] | (index("@semantic-release/git") or index("@semantic-release/changelog")) | not' <<<"$_m01_rc"
  check_cmd "$_m01_nom : release.yml inclus par la CI du projet" \
    grep -q 'release.yml' <<<"$(_m01_get "projects/$_m01_p/repository/files/.gitlab-ci.yml/raw?ref=main")"
  check_cmd "$_m01_nom : jeton d'accès de projet bot-release actif (Maintainer, api + write_repository, expiration)" \
    jq -e 'any(.[]?; .name == "bot-release" and .active == true and .revoked == false and .access_level == 40
                     and (.scopes | index("api")) and (.scopes | index("write_repository")) and .expires_at != null)' \
    <<<"$(_m01_get "projects/$_m01_p/access_tokens")"
  check_cmd "$_m01_nom : variable GITLAB_TOKEN protégée et masquée" \
    jq -e '.protected == true and .masked == true' <<<"$(_m01_get "projects/$_m01_p/variables/GITLAB_TOKEN")"
  check_cmd "$_m01_nom : étiquettes v* protégées" \
    jq -e 'any(.[]?; .name == "v*")' <<<"$(_m01_get "projects/$_m01_p/protected_tags")"
  check_cmd "$_m01_nom : au moins une release vX.Y.Z publiée" \
    jq -e 'any(.[]?; .tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))' <<<"$(_m01_get "projects/$_m01_p/releases?per_page=20")"
  _m01_pl="$(_m01_get "projects/$_m01_p/pipelines?ref=main&per_page=1" | jq -r '.[0].id // empty' 2>/dev/null || true)"
  check_cmd "$_m01_nom : le job release du dernier pipeline de main a réussi" \
    jq -e 'any(.[]?; .name == "release" and .status == "success")' <<<"$(_m01_get "projects/$_m01_p/pipelines/${_m01_pl:-0}/jobs?per_page=100")"
done

# --- 3. Branche majeure v1 de ci-templates --------------------------------------------------
_m01_tag="$(_m01_get "projects/$_m01_CT/repository/tags?order_by=version&search=%5Ev1.&per_page=1")"
_m01_tag_sha="$(jq -r '.[0].commit.id // empty' <<<"$_m01_tag" 2>/dev/null || true)"
_m01_v1_sha="$(_m01_get "projects/$_m01_CT/repository/branches/v1" | jq -r '.commit.id // empty' 2>/dev/null || true)"
check_cmd "plateforme/ci-templates : une version 1.x.y est publiée" test -n "$_m01_tag_sha"
check_cmd "plateforme/ci-templates : la branche v1 pointe sur la dernière version 1.x.y ($(jq -r '.[0].name // "?"' <<<"$_m01_tag" 2>/dev/null || echo '?'))" \
  test -n "$_m01_v1_sha" -a "$_m01_v1_sha" = "$_m01_tag_sha"
check_cmd "plateforme/ci-templates : pas de version majeure 2 publiée (les consommateurs suivent v1)" \
  jq -e 'length == 0' <<<"$(_m01_get "projects/$_m01_CT/repository/tags?search=%5Ev2.&per_page=1")"
