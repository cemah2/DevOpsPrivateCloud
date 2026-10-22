# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E44.sh — M19-E44 « Sous le capot : du git push au pod de job » : le compte rendu
# docs/livraison/ci/sous-le-capot.md existe, est commité, couvre les étapes demandées, cite un job réel
# du témoin ou de ci-labo et ne contient aucun secret. Lecture seule.

# shellcheck source=_m19-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-expert.sh"

title "M19-E44 — Sous le capot : du git push au pod de job"
require_cmd jq curl

_m19_e44_f='sous-le-capot.md'
check_cmd "compte rendu présent et commité (docs/livraison/ci/sous-le-capot.md)" _m19x_doc_commite "$_m19_e44_f"
_m19_e44_sections() {
  local m
  for m in '^#+ .*(push|réception)' '^#+ .*pipeline' '^#+ .*(runner|file|long polling)' '^#+ .*(pod|Kubernetes)' \
    '^#+ .*(artefact|téléversement|fin du job)' '^#+ .*[Rr]éponses'; do
    _m19x_doc_contient "$_m19_e44_f" "$m" || return 1
  done
}
check_cmd "sections : réception du push, création du pipeline, file et runner, pod, artefacts, réponses" _m19_e44_sections
_m19_e44_preuves() {
  local m
  for m in 'production_json\.log|api_json\.log' 'sidekiq' 'jobs/request' 'audit' 'helper' 'artifacts' 'PostReceive|CreatePipeline|pipeline_process'; do
    _m19x_doc_contient "$_m19_e44_f" "$m" || return 1
  done
}
check_cmd "preuves citées : journaux Rails et Sidekiq, /api/v4/jobs/request, audit Kubernetes, helper, artefacts" _m19_e44_preuves
_m19_e44_job_reel() {
  local f ids id p
  f="$(_m19x_doc "$_m19_e44_f")"
  [[ -n "$f" ]] || return 1
  ids="$(grep -Eo '(job|jobs/)[ #]?[0-9]{2,}' "$_m19x_depot/$f" | grep -Eo '[0-9]+' | sort -u | head -n 5)"
  for id in $ids; do
    for p in "$_m19x_temoin" formation/ci-labo; do
      gitlab_api "projects/$(_m19x_enc "$p")/jobs/$id" >/dev/null 2>&1 && return 0
    done
  done
  return 1
}
check_cmd "le compte rendu cite l'identifiant d'un job réel (témoin ou formation/ci-labo)" _m19_e44_job_reel
check_cmd "aucun jeton (glrt-, glpat-, glcbt-, jeton de job), clé privée ou JWT dans le compte rendu" _m19x_sans_secret "$_m19_e44_f"
