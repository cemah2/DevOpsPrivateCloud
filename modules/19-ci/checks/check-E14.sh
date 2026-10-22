# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E14.sh — M19-E14 : Services de job : une base PostgreSQL pour les tests d'intégration
# À lancer depuis adm01. Lecture seule : API GitLab (pipelines, jobs, rapports de tests, fichiers).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E14 — Services de job : une base PostgreSQL pour les tests d'intégration"
require_cmd jq yq curl

# Dernier pipeline de mediagenda/api (MR ou main) qui contient le job qualite:tests-integration.
_m19o_e14_pid=0
_m19o_e14_job=""
for _m19o_e14_id in $(_m19o_api "$_M19O_P_API/pipelines?order_by=id&sort=desc&per_page=15" | jq -r '.[].id' 2>/dev/null || true); do
  _m19o_e14_job="$(_m19o_jobs "$_M19O_P_API" "$_m19o_e14_id" | jq -c '[.[] | select(.name == "qualite:tests-integration")][0] // empty' 2>/dev/null || true)"
  if [[ -n "$_m19o_e14_job" ]]; then _m19o_e14_pid="$_m19o_e14_id"; break; fi
done
check_cmd "mediagenda/api : un pipeline récent contient le job qualite:tests-integration" test "$_m19o_e14_pid" != 0
check_cmd "le job qualite:tests-integration a réussi (pipeline $_m19o_e14_pid)" _m19o_json "$_m19o_e14_job" '.status == "success"'
check_cmd "il a publié un rapport JUnit (artefact junit)" _m19o_json "$_m19o_e14_job" 'any(.artifacts[]?; .file_type == "junit")'
check_cmd "le rapport de tests du pipeline contient des tests d'intégration (suite qualite:tests-integration non vide)" \
  _m19o_json "$(_m19o_api "$_M19O_P_API/pipelines/$_m19o_e14_pid/test_report_summary")" \
  'any(.test_suites[]?; .name == "qualite:tests-integration" and .total_count > 0)'

_m19o_e14_ci="$(_m19o_contenu "$_M19O_P_API" .gitlab-ci.yml)"
check_cmd "mediagenda/api (main) : composant qualite inclus avec integration: true" \
  bash -c 'yq -e ".include[] | select(.component | test(\"/qualite@\")) | .inputs.integration == true" <<<"$1" >/dev/null 2>&1' _ "$_m19o_e14_ci"
# Les images des services viennent des valeurs par défaut du composant ou d'entrées du projet : dans
# les deux cas, Harbor ET une empreinte.
_m19o_e14_v="$(_m19o_version_composant "$_m19o_e14_ci" qualite)"
_m19o_e14_tpl="$(_m19o_contenu "$_M19O_P_TPL" templates/qualite/template.yml "${_m19o_e14_v:-main}")"
_m19o_e14_images() {
  local surcharges
  surcharges="$(yq -r '.include[] | select(.component | test("/qualite@")) | .inputs | (.image_postgresql // ""), (.image_valkey // "")' <<<"$1" 2>/dev/null | grep -v '^$' || true)"
  printf '%s\n' "$surcharges" | grep -v '^$' | grep -qvE '^registry\.par1\.medisphere\.internal/.+@sha256:[a-f0-9]{64}$' && return 1
  grep -qE 'postgres:18[^@]*@sha256:[a-f0-9]{64}' <<<"$2" && grep -qE 'valkey:8\.1[^@]*@sha256:[a-f0-9]{64}' <<<"$2"
}
check_cmd "services PostgreSQL 18 et Valkey 8.1 par Harbor, épinglés par empreinte (composant qualite ${_m19o_e14_v:-?})" \
  _m19o_e14_images "$_m19o_e14_ci" "$_m19o_e14_tpl"
check_output "journal ~/m19/e14/journal.md (services, localhost/alias, attente)" 'localhost|alias|127\.0\.0\.1' \
  cat "$_M19O_TRAVAIL/e14/journal.md"
