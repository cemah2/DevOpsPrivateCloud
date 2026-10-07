# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E29.sh — M04-E29 « Détecter la dérive de configuration »
# Planification quotidienne sur main, jeton d'alerte protégé, rapport conservé 90 jours, ticket
# « derive » créé puis fermé, dernière détection conforme, outil utilisable sur adm01.

# shellcheck source=_m04-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-production.sh"

title "M04-E29 — Détection de dérive"
require_cmd jq curl

# _m04_e29_planif — une planification active sur main porte la variable PLANIF=derive.
_m04_e29_planif() {
  local ids id
  ids="$(gitlab_api "$_M04_PROJET/pipeline_schedules?scope=active" 2>/dev/null \
    | jq -r '.[] | select(.ref == "main" or .ref == "refs/heads/main") | .id')" || return 1
  for id in $ids; do
    gitlab_api "$_M04_PROJET/pipeline_schedules/$id" 2>/dev/null \
      | jq -e 'any(.variables[]?; .key == "PLANIF" and .value == "derive")' >/dev/null && return 0
  done
  return 1
}

# _m04_e29_dernier_job — JSON du dernier job « derive » terminé d'un pipeline planifié.
_m04_e29_dernier_job() {
  local ids pid j
  ids="$(gitlab_api "$_M04_PROJET/pipelines?source=schedule&ref=main&per_page=20" 2>/dev/null | jq -r '.[].id')" || return 1
  for pid in $ids; do
    j="$(gitlab_api "$_M04_PROJET/pipelines/$pid/jobs?per_page=100" 2>/dev/null \
      | jq -c '[.[] | select(.name == "derive" and (.status == "success" or .status == "failed"))][0] // empty')" || continue
    if [[ -n "$j" ]]; then printf '%s\n' "$j"; return 0; fi
  done
  return 1
}

# _m04_e29_rapport_conserve — le dernier job derive a des artefacts conservés au moins 80 jours.
_m04_e29_rapport_conserve() {
  local j
  j="$(_m04_e29_dernier_job)" || return 1
  jq -e '(.artifacts // []) | length > 0' >/dev/null <<<"$j" || return 1
  jq -e 'def t: sub("\\.[0-9]+"; "") | fromdateiso8601;
    .artifacts_expire_at != null and .finished_at != null
    and ((.artifacts_expire_at | t) - (.finished_at | t)) >= 80 * 86400' >/dev/null 2>&1 <<<"$j"
}

# _m04_e29_conforme — la dernière détection planifiée est conforme (job réussi).
_m04_e29_conforme() {
  local j
  j="$(_m04_e29_dernier_job)" || return 1
  jq -e '.status == "success"' >/dev/null <<<"$j"
}

title "Planification et secrets (GitLab)"
check_cmd "pipeline planifié actif sur main avec PLANIF=derive" _m04_e29_planif
check_cmd ".gitlab-ci.yml sur main : job derive en pipeline planifié" \
  _m04_fichier_main_contient .gitlab-ci.yml 'PLANIF[[:space:]]*==[[:space:]]*"derive"'
check_cmd "outils/derive.sh présent sur main" _m04_fichier_main outils/derive.sh
check_cmd "DERIVE_TOKEN : protégé et masqué" \
  _m04_variable_ok DERIVE_TOKEN '.protected and (.masked or (.masked_and_hidden // false))'

title "Détections"
check_cmd "une détection planifiée a produit un rapport conservé environ 90 jours" _m04_e29_rapport_conserve
check_cmd "un ticket « derive » a été ouvert par une détection" \
  _m04_api_ok "$_M04_PROJET/issues?labels=derive&state=all&per_page=20" 'length > 0'
check_cmd "un ticket « derive » a été fermé après correction" \
  _m04_api_ok "$_M04_PROJET/issues?labels=derive&state=closed&per_page=20" 'length > 0'
check_cmd "la dernière détection planifiée est conforme" _m04_e29_conforme

title "Poste d'administration"
check_cmd "outils/derive.sh exécutable dans le clone local" test -x "$_M04_SRC/outils/derive.sh"
