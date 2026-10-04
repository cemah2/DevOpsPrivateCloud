# shellcheck shell=bash
#
# check-E35.sh — M01-E35 « Workflow complet en temps limité »
# Lancé depuis adm01. Lecture seule : l'historique est relu dans un clone nu
# temporaire (SSH, ta clé), supprimé à la fin. Le projet contrôlé est le dernier
# créé par ressources/M01-E35/fabriquer-depot.sh.

title "M01-E35 — Workflow complet en temps limité"
require_cmd git jq curl

_m01_get() { gitlab_api "$1" 2>/dev/null || true; }
_m01_ETAT="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M01-E35/projet"
_m01_HOTE="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_m01_HOTE="${_m01_HOTE#https://}"
_m01_CHEMIN="$(head -n 1 "$_m01_ETAT" 2>/dev/null || true)"
_m01_P="${_m01_CHEMIN//\//%2F}"

check_cmd "projet de l'épreuve connu ($_m01_ETAT)" test -n "$_m01_CHEMIN"
check_cmd "projet ${_m01_CHEMIN:-?} présent sur la forge" jq -e '.id' <<<"$(_m01_get "projects/${_m01_P:-x}")"

# --- 1. La MR -------------------------------------------------------------------------------
_m01_mr="$(_m01_get "projects/${_m01_P:-x}/merge_requests?state=merged&target_branch=main&per_page=1")"
_m01_iid="$(jq -r '.[0].iid // empty' <<<"$_m01_mr" 2>/dev/null || true)"
check_cmd "une MR vers main a été fusionnée" test -n "$_m01_iid"
check_cmd "toutes ses discussions sont résolues (dont la revue de Karim)" \
  jq -e '[.[]? | .notes[] | select(.resolvable) | .resolved] | length > 0 and all' \
  <<<"$(_m01_get "projects/${_m01_P:-x}/merge_requests/${_m01_iid:-0}/discussions?per_page=100")"
check_cmd "main est toujours protégée (push : personne)" \
  jq -e '.push_access_levels | length > 0 and all(.access_level == 0)' \
  <<<"$(_m01_get "projects/${_m01_P:-x}/protected_branches/main")"

# --- 2. L'historique de main (clone temporaire) ---------------------------------------------
_m01_tmp="$(mktemp -d)"
git clone -q --bare "git@$_m01_HOTE:${_m01_CHEMIN:-x}.git" "$_m01_tmp/d.git" 2>/dev/null || true
_m01_g() { git -C "$_m01_tmp/d.git" "$@" 2>/dev/null; }
check_cmd "clone de contrôle du projet (SSH)" _m01_g rev-parse --verify -q main
check_cmd "aucun jeton glpat- dans l'historique de main ni des étiquettes" \
  bash -c '! git -C "$1" log -p --all | grep -Eq "glpat-[0-9A-Za-z_-]{20}"' _ "$_m01_tmp/d.git"
check_cmd "commits arrivés depuis v1.0.0 (hors fusions) : tous conformes à Conventional Commits" \
  bash -c 's=$(git -C "$1" log --no-merges --format=%s v1.0.0..main) && [ -n "$s" ] && ! grep -Evq "^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([[:alnum:]._/-]+\))?!?: [^[:space:]]" <<<"$s"' _ "$_m01_tmp/d.git"
check_cmd "aucun commit fixup!/squash! ni « WIP » sur main" \
  bash -c '! git -C "$1" log --format=%s v1.0.0..main | grep -Eiq "^(fixup!|squash!|amend!|wip)"' _ "$_m01_tmp/d.git"
check_cmd "le correctif de fuseau horaire de Karim n'a pas été perdu" \
  bash -c 'git -C "$1" show main:rappel.sh | grep -q "TZ=Europe/Paris"' _ "$_m01_tmp/d.git"
check_cmd "la fonction SMS est livrée" bash -c 'git -C "$1" show main:rappel.sh | grep -q "envoyer_sms"' _ "$_m01_tmp/d.git"
check_cmd "revue traitée : MEDISMS_URL surchargeable par l'environnement" \
  bash -c 'git -C "$1" show main:rappel.sh | grep -Eq "MEDISMS_URL=\"?\\$\\{MEDISMS_URL:-"' _ "$_m01_tmp/d.git"
rm -rf "$_m01_tmp"

# --- 3. Pipeline et version ---------------------------------------------------------------------
check_cmd "dernier pipeline de main réussi" \
  jq -e '.[0].status == "success"' <<<"$(_m01_get "projects/${_m01_P:-x}/pipelines?ref=main&per_page=1")"
check_cmd "release v1.1.0 publiée par la chaîne de release" \
  jq -e 'any(.[]?; .tag_name == "v1.1.0")' <<<"$(_m01_get "projects/${_m01_P:-x}/releases?per_page=20")"
check_cmd "variable GITLAB_TOKEN du projet protégée et masquée" \
  jq -e '.protected == true and .masked == true' <<<"$(_m01_get "projects/${_m01_P:-x}/variables/GITLAB_TOKEN")"
