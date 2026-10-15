# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E13.sh — M17-E13 « Le pipeline du chart » : pipeline de MR/main (lint, tests, release),
# pipeline d'étiquette (paquet, poussée, signature), chart publié et signé dans Harbor, MR rouge.
# Lecture seule (API GitLab et Harbor en lecture, cosign verify).

# shellcheck source=_m17-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m17-production.sh"

title "M17-E13 — Le pipeline du chart"
require_cmd jq curl

_e13_p="mediagenda/chart"
check_cmd "projet $_e13_p : .gitlab-ci.yml sur main" _m17p_gl_existe "$_e13_p" .gitlab-ci.yml
check_cmd "projet $_e13_p : .releaserc.json sur main (version par semantic-release)" _m17p_gl_existe "$_e13_p" .releaserc.json
check_output "ct.yaml n'exige plus d'incrément de version dans les MR" 'check-version-increment:[[:space:]]*false' \
  _m17p_gl_fichier "$_e13_p" ct.yaml
check_cmd "dernier pipeline de main réussi" _m17p_gl_pipeline_ok "$_e13_p" main
check_cmd "pipeline de main : jobs de lint, de tests helm-unittest et de release réussis" \
  _m17p_gl_jobs_ok "$_e13_p" main 'lint' 'unittest' '^release$'

_e13_v="$(_m17p_gl_derniere_version "$_e13_p")" || _e13_v=""
if [[ -n "$_e13_v" ]]; then
  check_cmd "étiquette v$_e13_v : pipeline réussi" _m17p_gl_pipeline_ok "$_e13_p" "v$_e13_v"
  check_cmd "étiquette v$_e13_v : jobs de paquet, de poussée et de signature réussis" \
    _m17p_gl_jobs_ok "$_e13_p" "v$_e13_v" 'paquet|package' 'pousser|push' 'sign'
  _e13_art="$(_m17p_harbor_artefact charts mediagenda "$_e13_v")" || _e13_art=""
  check_cmd "Harbor : charts/mediagenda:$_e13_v publié" test -n "$_e13_art"
  if [[ -n "$_e13_art" ]]; then
    _e13_dig="$(jq -r '.digest' <<<"$_e13_art")" || _e13_dig=""
    _e13_rc=0
    _m17p_cosign_ok "$_m17p_harbor_hote/charts/mediagenda@$_e13_dig" || _e13_rc=$?
    if ((_e13_rc == 2)); then
      check_cmd "Harbor : une signature est attachée au chart $_e13_v" _m17p_jq "$_e13_art" '(.accessories // []) | length > 0'
      skip "cosign verify avec la clé publique MédiSphère" "cosign, docs/registre/cosign.pub ou identifiants Harbor des checks absents"
    else
      check_cmd "cosign verify : chart $_e13_v signé par la clé MédiSphère (par digest)" test "$_e13_rc" -eq 0
    fi
  fi
  check_cmd "la version publiée n'est pas la 1.0.0 d'un historique repris de zéro" test "$_e13_v" != "1.0.0"
else
  check_cmd "au moins une étiquette vX.Y.Z posée par semantic-release" false
fi

# Une MR dont le pipeline a échoué (MR de test rouge) prouve que les contrôles bloquent.
_e13_mr_rouge() {
  local iid
  for iid in $(gitlab_api "projects/$(_m17p_enc "$_e13_p")/merge_requests?state=all&per_page=30" 2>/dev/null | jq -r '.[].iid' 2>/dev/null); do
    gitlab_api "projects/$(_m17p_enc "$_e13_p")/merge_requests/$iid" 2>/dev/null \
      | jq -e '.head_pipeline.status == "failed"' >/dev/null 2>&1 && return 0
  done
  return 1
}
check_cmd "une MR de test a un pipeline en échec (contrôles bloquants)" _e13_mr_rouge
