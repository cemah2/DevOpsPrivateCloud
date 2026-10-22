# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E12.sh — M19-E12 : Pipelines enfants, multi-projets et déclencheurs
# À lancer depuis adm01. Lecture seule : API GitLab (pipelines, jobs déclencheurs « bridges »,
# portée du CI_JOB_TOKEN).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E12 — Pipelines enfants, multi-projets et déclencheurs"
require_cmd jq curl

# L'aval est reconnu à son URL (le champ downstream_pipeline des « bridges » ne donne pas le projet).
_M19O_E12_RE_DEP='/mediagenda/deploiement/-/pipelines/'
_m19o_e12_tag="$(_m19o_pipeline_etiquette "$_M19O_P_CHART")"
_m19o_e12_tid="$(jq -r '.id // 0' <<<"${_m19o_e12_tag:-null}" 2>/dev/null || echo 0)"
check_cmd "mediagenda/chart : le pipeline de la dernière étiquette vX.Y.Z a réussi" _m19o_json "$_m19o_e12_tag" '.status == "success"'

# Job déclencheur de ce pipeline dont l'aval est dans mediagenda/deploiement.
_m19o_e12_ponts="$(_m19o_api "$_M19O_P_CHART/pipelines/$_m19o_e12_tid/bridges")"
check_cmd "mediagenda/chart : un job déclencheur de ce pipeline a créé un pipeline dans mediagenda/deploiement" \
  _m19o_json "$_m19o_e12_ponts" 'any(.[]; (.downstream_pipeline.web_url // "") | test($re))' --arg re "$_M19O_E12_RE_DEP"
_m19o_e12_aval="$(jq -r --arg re "$_M19O_E12_RE_DEP" \
  '[.[] | select((.downstream_pipeline.web_url // "") | test($re)) | .downstream_pipeline.id][0] // 0' <<<"${_m19o_e12_ponts:-[]}" 2>/dev/null || echo 0)"
check_cmd "mediagenda/deploiement : ce pipeline aval (source « pipeline ») a réussi" \
  _m19o_json "$(_m19o_api "$_M19O_P_DEP/pipelines/$_m19o_e12_aval")" '.status == "success" and .source == "pipeline"'
check_cmd "mediagenda/chart : le job déclencheur reflète le statut de l'aval (réussi)" \
  _m19o_json "$_m19o_e12_ponts" 'any(.[]; ((.downstream_pipeline.web_url // "") | test($re)) and .status == "success")' --arg re "$_M19O_E12_RE_DEP"

# Pipeline ENFANT (même projet, configuration générée) dans le pipeline aval.
_m19o_e12_enfants="$(_m19o_api "$_M19O_P_DEP/pipelines/$_m19o_e12_aval/bridges")"
check_cmd "mediagenda/deploiement : le pipeline aval contient un pipeline enfant réussi" \
  _m19o_json "$_m19o_e12_enfants" 'any(.[]; ((.downstream_pipeline.web_url // "") | test($re))
    and .downstream_pipeline.status == "success")' --arg re "$_M19O_E12_RE_DEP"
_m19o_e12_enfant="$(jq -r --arg re "$_M19O_E12_RE_DEP" \
  '[.[] | select((.downstream_pipeline.web_url // "") | test($re)) | .downstream_pipeline.id][0] // 0' <<<"${_m19o_e12_enfants:-[]}" 2>/dev/null || echo 0)"
check_cmd "le pipeline enfant valide plusieurs overlays (au moins 2 jobs)" \
  _m19o_json "$(_m19o_jobs "$_M19O_P_DEP" "$_m19o_e12_enfant")" '[.[] | select(.status == "success")] | length >= 2'

# Portée du CI_JOB_TOKEN de mediagenda/chart : liste d'autorisation active, deploiement autorisé.
check_cmd "mediagenda/chart : la liste d'autorisation entrante du CI_JOB_TOKEN est active" \
  _m19o_json "$(_m19o_api "$_M19O_P_CHART/job_token_scope")" '.inbound_enabled == true'
check_cmd "mediagenda/chart : mediagenda/deploiement figure dans cette liste" \
  _m19o_json "$(_m19o_api "$_M19O_P_CHART/job_token_scope/allowlist?per_page=100")" \
  'any(.[]; .path_with_namespace == "mediagenda/deploiement")'
check_output "journal ~/m19/e12/journal.md (auteur de l'aval, variables visibles, strategy)" 'strategy|auteur|mirror' \
  cat "$_M19O_TRAVAIL/e12/journal.md"
