# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E21.sh — M19-E21 : Revue : le .gitlab-ci.yml du stagiaire
# Vérifie la VERSION CORRIGÉE (branche revue-lucas de formation/ci-labo) ; la revue elle-même
# s'auto-évalue avec le corrigé. À lancer depuis adm01. Lecture seule : API GitLab.

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E21 — Revue : le .gitlab-ci.yml du stagiaire (version corrigée)"
require_cmd jq yq curl

_m19o_e21_ci="$(_m19o_contenu "$_M19O_P_LABO" .gitlab-ci.yml revue-lucas)"
check_cmd "formation/ci-labo : .gitlab-ci.yml sur la branche revue-lucas" test -n "$_m19o_e21_ci"
check_cmd "n'inclut que des composants de plateforme/ci-templates en v2.x.y épinglée" _m19o_que_des_composants "$_m19o_e21_ci"
check_cmd "aucun Docker-in-Docker ni privilège" bash -c '[[ -n "$1" ]] && ! grep -qiE "dind|privileged|DOCKER_HOST" <<<"$1"' _ "$_m19o_e21_ci"
check_cmd "aucune image « latest » ni image hors de Harbor" \
  bash -c '[[ -n "$1" ]] && ! grep -qE ":latest\b" <<<"$1" && ! yq -r ".. | select(has(\"image\")?) | .image | select(type == \"!!str\")" <<<"$1" 2>/dev/null | grep -qvE "^registry\.par1\.medisphere\.internal/"' _ "$_m19o_e21_ci"
check_cmd "aucun only/except (rules partout)" \
  bash -c '[[ -n "$1" ]] && yq -e "[.. | select(tag == \"!!map\" and (has(\"only\") or has(\"except\")))] | length == 0" <<<"$1" >/dev/null 2>&1' _ "$_m19o_e21_ci"
check_cmd "aucun secret en clair (mot de passe, jeton) dans le fichier" \
  bash -c '[[ -n "$1" ]] && ! grep -qiE "(password|passwd|token|secret)[A-Z_]*: *\"?[A-Za-z0-9+/=]{8,}" <<<"$1"' _ "$_m19o_e21_ci"
check_cmd "workflow:rules présent (pas de pipelines en double)" \
  bash -c 'yq -e ".workflow.rules | length > 0" <<<"$1" >/dev/null 2>&1' _ "$_m19o_e21_ci"
# Dernier pipeline de la branche : celui de sa MR s'il y en a une (une MR ouverte supprime les pipelines
# de branche, workflow:rules), sinon le dernier pipeline de branche. La liste des MR ne donne pas
# head_pipeline : lecture de la MR elle-même.
_m19o_e21_iid="$(_m19o_api "$_M19O_P_LABO/merge_requests?source_branch=revue-lucas&state=all&order_by=created_at&sort=desc&per_page=1" \
  | jq -r '.[0].iid // empty' 2>/dev/null || true)"
_m19o_e21_pl=""
if [[ -n "$_m19o_e21_iid" ]]; then
  _m19o_e21_pl="$(_m19o_api "$_M19O_P_LABO/merge_requests/$_m19o_e21_iid" | jq -c '.head_pipeline // empty' 2>/dev/null || true)"
fi
[[ -n "$_m19o_e21_pl" ]] || _m19o_e21_pl="$(_m19o_pipeline "$_M19O_P_LABO" "ref=revue-lucas")"
check_cmd "formation/ci-labo : le dernier pipeline de revue-lucas (MR ou branche) a réussi" \
  _m19o_json "$_m19o_e21_pl" '.status == "success"'
