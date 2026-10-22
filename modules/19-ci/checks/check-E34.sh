# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E34.sh — M19-E34 « Un pipeline en temps limité » (MédiAnnuaire, exigences du dossier).
# À lancer à T4 depuis adm01. Lecture seule : configuration fusionnée, pipelines, jobs, réglages et
# tickets de mediagenda/annuaire (API de GitLab), artefact dans Harbor.

# shellcheck source=_m19-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-production.sh"

title "M19-E34 — MédiAnnuaire dans la chaîne standard"
require_cmd jq curl

_m19_e34_p=mediagenda/annuaire
_m19_e34_l="$(_m19p_lint "$_m19_e34_p")"
title "Exigence 1 : composants seulement"
check_cmd "configuration valide, n'incluant que des composants" _m19p_seulement_composants "$_m19_e34_l"
for _m19_e34_c in qualite construction-image securite; do
  check_cmd "composant $_m19_e34_c inclus en 2.2.0 ou plus" _m19p_inclut_composant "$_m19_e34_l" "$_m19_e34_c" 2.2.0
done

title "Exigences 2, 3 et 6 : pipelines"
check_cmd "aucune image « latest » ni référence à ctr01 dans la configuration fusionnée" bash -c \
  'm="$(jq -r ".merged_yaml // empty" <<<"$1")"; [[ -n "$m" ]] && ! grep -Eq ":latest([[:space:]\"]|$)|ctr01" <<<"$m"' _ "$_m19_e34_l"
check_cmd "dernier pipeline de main réussi" _m19p_jq "$(_m19p_pipeline_main "$_m19_e34_p")" '.status == "success"'
_m19_e34_pl="$(_m19p_pipeline_etiquette "$_m19_e34_p" '^v1\.([1-9]|[1-9][0-9])\.[0-9]+$')"
check_cmd "pipeline de l'étiquette v1.1.0 (ou plus) réussi" _m19p_jq "$_m19_e34_pl" '.status == "success"'
if [[ "$_m19_e34_pl" != null ]]; then
  _m19_e34_j="$(_m19p_jobs "$_m19_e34_p" "$(jq -r .id <<<"$_m19_e34_pl")")"
  check_cmd "aucun job sur runner02 (étiquette docker)" _m19p_jq "$_m19_e34_j" \
    'length > 0 and all(.[]; (.tag_list | index("docker") | not) and ((.runner.description // "") | test("runner02") | not))'
  check_cmd "signature et attestations sur $_M19P_RUNNER_PROTEGE" _m19p_job_sur "$_m19_e34_j" securite:signature "$_M19P_RUNNER_PROTEGE"
fi
check_cmd "Harbor : medisphere/annuaire v1.1.0 (ou plus) signée et attestée" \
  _m19p_signee_attestee "$(_m19p_artefact_version medisphere annuaire '^v1\.([1-9]|[1-9][0-9])\.[0-9]+$')"

title "Exigence 4 : pipeline de MR"
_m19_e34_mr="$(_m19p_pipeline_mr "$_m19_e34_p")"
check_cmd "dernier pipeline de MR réussi en moins de 10 min" _m19p_jq "$_m19_e34_mr" '.status == "success"'
if [[ "$_m19_e34_mr" != null ]]; then
  check_cmd "durée du pipeline de MR < 600 s" _m19p_jq \
    "$(_m19p_gl "projects/$(_m19p_p "$_m19_e34_p")/pipelines/$(jq -r .id <<<"$_m19_e34_mr")")" '(.duration // 99999) < 600'
fi

title "Exigence 5 : conformité"
check_cmd "fusion seulement si le pipeline a réussi" \
  _m19p_jq "$(_m19p_gl "projects/$(_m19p_p "$_m19_e34_p")")" '.only_allow_merge_if_pipeline_succeeds == true'
check_output "aucun ticket conformite-ci ouvert" '^0$' _m19p_issues_ouvertes "$_m19_e34_p" conformite-ci
