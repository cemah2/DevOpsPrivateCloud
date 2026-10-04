# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E24.sh — M01-E24 « Pipeline de qualité obligatoire avant fusion »
# Lancé depuis adm01. Lecture seule (runner01 en SSH, API GitLab).

title "M01-E24 — Pipeline de qualité obligatoire avant fusion"
require_cmd ssh jq curl

_m01_get() { gitlab_api "$1" 2>/dev/null || true; }
_m01_CT="plateforme%2Fci-templates"
_m01_MS="plateforme%2Fmedisphere"

# --- 1. Outillage Node sur runner01 ------------------------------------------------------
check_ssh_output "runner01 : Node.js 24" runner01 '^v24\.' 'node --version'
check_ssh "runner01 : /opt/release-tools installé depuis un verrou (commitlint, semantic-release)" runner01 \
  'd=/opt/release-tools; test -s $d/package-lock.json && test -x $d/node_modules/.bin/commitlint && test -x $d/node_modules/.bin/semantic-release'
check_ssh "runner01 : /opt/release-tools non modifiable par l'utilisateur des jobs" runner01 \
  'cd /tmp && ! sudo -n -u gitlab-runner test -w /opt/release-tools && ! sudo -n -u gitlab-runner test -w /opt/release-tools/node_modules && ! sudo -n -u gitlab-runner test -w /opt/release-tools/node_modules/.bin'

# --- 2. Projet des gabarits ---------------------------------------------------------------
_m01_qualite="$(_m01_get "projects/$_m01_CT/repository/files/templates%2Fqualite.yml/raw?ref=main")"
check_cmd "plateforme/ci-templates : templates/qualite.yml présent sur main" test -n "$_m01_qualite"
for _m01_job in pre-commit commitlint gitleaks; do
  check_cmd "templates/qualite.yml définit le job $_m01_job" grep -Eq "^${_m01_job}:" <<<"$_m01_qualite"
done
check_cmd "templates/qualite.yml : jobs sur l'étiquette shell" grep -Eq 'tags:.*shell' <<<"$_m01_qualite"
check_cmd "templates/qualite.yml : règles de workflow (pas de pipelines en double)" grep -Eq '^workflow:' <<<"$_m01_qualite"
check_cmd "plateforme/ci-templates : verrou des outils Node versionné (package-lock.json)" \
  test -n "$(_m01_get "projects/$_m01_CT/repository/tree?ref=main&recursive=true&per_page=100" | jq -r '.[]?.path' 2>/dev/null | grep -E '(^|/)package-lock\.json$')"
check_cmd "plateforme/ci-templates : branche v1 présente et protégée" \
  jq -e '.protected == true' <<<"$(_m01_get "projects/$_m01_CT/repository/branches/v1")"

# --- 3. Projets consommateurs -------------------------------------------------------------
_m01_ci_ms="$(_m01_get "projects/$_m01_MS/repository/files/.gitlab-ci.yml/raw?ref=main")"
check_cmd "plateforme/medisphere : .gitlab-ci.yml inclut plateforme/ci-templates" \
  grep -Eq 'project:[[:space:]]*["'"'"']?plateforme/ci-templates' <<<"$_m01_ci_ms"
check_cmd "plateforme/medisphere : inclusion figée sur ref v1" grep -Eq 'ref:[[:space:]]*["'"'"']?v1["'"'"']?[[:space:]]*$' <<<"$_m01_ci_ms"
check_cmd "plateforme/medisphere : inclusion de templates/qualite.yml" grep -q 'templates/qualite.yml' <<<"$_m01_ci_ms"
for _m01_p in "$_m01_MS" "$_m01_CT"; do
  _m01_nom="${_m01_p//%2F//}"
  _m01_proj="$(_m01_get "projects/$_m01_p")"
  check_cmd "$_m01_nom : fusion seulement si le pipeline réussit" \
    jq -e '.only_allow_merge_if_pipeline_succeeds == true' <<<"$_m01_proj"
  check_cmd "$_m01_nom : un pipeline ignoré ne vaut pas réussite" \
    jq -e '.allow_merge_on_skipped_pipeline == false' <<<"$_m01_proj"
  check_cmd "$_m01_nom : dernier pipeline de main réussi" \
    jq -e '.[0].status == "success"' <<<"$(_m01_get "projects/$_m01_p/pipelines?ref=main&per_page=1")"
done

# --- 4. Pipelines de MR -------------------------------------------------------------------
_m01_pid="$(_m01_get "projects/$_m01_MS/pipelines?source=merge_request_event&per_page=1" | jq -r '.[0].id // empty' 2>/dev/null || true)"
_m01_jobs="$(_m01_get "projects/$_m01_MS/pipelines/${_m01_pid:-0}/jobs?per_page=100")"
check_cmd "plateforme/medisphere : un pipeline de MR existe" test -n "$_m01_pid"
check_cmd "ce pipeline de MR contient les jobs commitlint et gitleaks" \
  jq -e '(map(.name) | index("commitlint")) and (map(.name) | index("gitleaks"))' <<<"$_m01_jobs"
if _m01_get "projects/$_m01_MS/repository/files/.pre-commit-config.yaml?ref=main" | grep -q '"file_name"'; then
  check_cmd "ce pipeline de MR contient le job pre-commit" jq -e 'map(.name) | index("pre-commit")' <<<"$_m01_jobs"
else
  skip "job pre-commit dans le pipeline de MR" "pas de .pre-commit-config.yaml sur main de plateforme/medisphere"
fi
check_cmd "ces jobs ont tourné sur un runner étiqueté shell" \
  jq -e 'any(.[]; (.tag_list // []) | index("shell"))' <<<"$_m01_jobs"
check_cmd "le blocage a été éprouvé : un job commitlint ou gitleaks en échec existe" \
  test -n "$( { _m01_get "projects/$_m01_MS/jobs?scope[]=failed&per_page=100"; _m01_get "projects/$_m01_CT/jobs?scope[]=failed&per_page=100"; } \
    | jq -r '.[]? | select(.name == "commitlint" or .name == "gitleaks") | .id' 2>/dev/null | head -n 1)"
