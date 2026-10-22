# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E13.sh — M19-E13 : Pipelines de MR : rapports de tests et couverture
# À lancer depuis adm01. Lecture seule : API GitLab (MR, pipelines, rapports de tests, réglages).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E13 — Pipelines de MR : rapports de tests et couverture"
require_cmd jq curl

# Dernière MR de mediagenda/api qui a un pipeline (ouverte ou fusionnée).
_m19o_e13_mr="$(_m19o_api "$_M19O_P_API/merge_requests?state=all&order_by=updated_at&sort=desc&per_page=20" \
  | jq -r '[.[] | .iid][]' 2>/dev/null | while read -r iid; do
      p="$(_m19o_api "$_M19O_P_API/merge_requests/$iid" | jq -r '.head_pipeline.id // empty' 2>/dev/null || true)"
      [[ -n "$p" ]] && { echo "$iid $p"; break; }
    done || true)"
read -r _m19o_e13_iid _m19o_e13_pid <<<"${_m19o_e13_mr:-0 0}"
check_cmd "mediagenda/api : une MR récente a un pipeline (MR !$_m19o_e13_iid)" test "$_m19o_e13_pid" != 0
check_cmd "ce pipeline publie un rapport de tests non vide (onglet Tests)" \
  _m19o_json "$(_m19o_api "$_M19O_P_API/pipelines/$_m19o_e13_pid/test_report_summary")" '.total.count > 0'
check_cmd "ce pipeline a une couverture renseignée (expression coverage)" \
  _m19o_json "$(_m19o_api "$_M19O_P_API/pipelines/$_m19o_e13_pid")" '.coverage != null and (.coverage | tonumber) > 0'
check_cmd "le job qualite:tests de ce pipeline a téléversé un rapport Cobertura" \
  _m19o_json "$(_m19o_jobs "$_M19O_P_API" "$_m19o_e13_pid")" \
  'any(.[]; .name == "qualite:tests" and any(.artifacts[]?; .file_type == "cobertura"))'

for _m19o_e13_p in "$_M19O_P_API" "$_M19O_P_DEP" "$_M19O_P_TPL"; do
  _m19o_e13_nom="$(printf '%s' "${_m19o_e13_p#projects/}" | sed 's/%2F/\//')"
  check_cmd "$_m19o_e13_nom : « Pipelines must succeed » activé, pipelines sautés non considérés comme réussis" \
    _m19o_json "$(_m19o_api "$_m19o_e13_p")" \
    '.only_allow_merge_if_pipeline_succeeds == true and (.allow_merge_on_skipped_pipeline // false) == false'
done
check_output "mediagenda/api (main) : pytest-cov dans pyproject.toml" 'pytest-cov' _m19o_contenu "$_M19O_P_API" pyproject.toml
check_output "mediagenda/api (main) : pytest-cov verrouillé dans uv.lock" 'name = "pytest-cov"' _m19o_contenu "$_M19O_P_API" uv.lock
