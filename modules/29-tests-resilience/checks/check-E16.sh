# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E16.sh — M29-E16 « Journée de jeu : hypothèse, mesure, rapport » : rapport publié avec les
# sections du gabarit, expériences versionnées dans journees-de-jeu/ (recette seulement, durées),
# issues d'actions étiquetées journee-de-jeu. Lecture seule. Le fond s'auto-évalue avec le corrigé.

# shellcheck source=_m29-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-production.sh"

title "M29-E16 — Journée de jeu"
require_cmd jq curl yq

check_cmd "rapport docs/qualite/journees-de-jeu/AAAA-MM-JJ-*.md : préparation, chronologie, hypothèses, détection, actions" \
  _m29p_doc docs/qualite/journees-de-jeu '^[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$' \
  '^#+ .*Pr[ée]paration' '^#+ .*Chronologie' 'hypoth' '^#+ .*D[ée]tection' '^#+ .*Actions'

_m29_e16_docs="$(_m29p_yaml_json "$_m29p_resilience" journees-de-jeu)" || true
[[ -n "$_m29_e16_docs" ]] || _m29_e16_docs='[]'
# Nombre d'expériences jouées : objets de chaos directs + modèles de chaos des Workflow.
_m29_e16_nb() {
  jq '[.[] | select((.apiVersion // "") | startswith("chaos-mesh.org/"))
       | if .kind == "Workflow" then (.spec.templates[]? | select(.templateType | test("Chaos$")))
         elif .kind == "Schedule" or .kind == "StatusCheck" then empty else . end] | length' <<<"$_m29_e16_docs" 2>/dev/null || echo 0
}
check_cmd "journees-de-jeu/ (main) : au moins trois expériences versionnées" bash -c '[[ "$1" -ge 3 ]]' _ "$(_m29_e16_nb)"
check_cmd "journees-de-jeu/ : toute expérience directe a une durée" \
  bash -c '[[ "$(jq length <<<"$2")" -gt 0 && "$(jq "$1" <<<"$2")" == 0 ]]' _ "$_m29p_jq_sans_duree" "$_m29_e16_docs"
check_cmd "journees-de-jeu/ : seuls mediagenda-recette, medinotif-recette (ou wb-essais) sont visés" \
  bash -c '[[ "$(jq length <<<"$2")" -gt 0 && "$(jq "$1" <<<"$2")" == 0 ]]' _ "$_m29p_jq_espaces_hors_recette" "$_m29_e16_docs"
check_cmd "plateforme/resilience : au moins deux issues étiquetées journee-de-jeu" \
  bash -c '[[ "$1" -ge 2 ]]' _ "$(_m29p_issues "$_m29p_resilience" journee-de-jeu)"
