# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E11.sh — M19-E11 : Le pipeline standard de MédiAgenda
# À lancer depuis adm01. Lecture seule : API GitLab (fichiers, pipelines, jobs), API Harbor (robot de
# lecture des checks : accessoires de signature de l'image).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E11 — Le pipeline standard de MédiAgenda"
require_cmd jq yq curl

_m19o_e11_ci="$(_m19o_contenu "$_M19O_P_API" .gitlab-ci.yml)"
check_cmd "mediagenda/api (main) : .gitlab-ci.yml n'inclut que des composants de plateforme/ci-templates en v2.x.y épinglée" \
  _m19o_que_des_composants "$_m19o_e11_ci"
for _m19o_e11_c in qualite construction-image securite; do
  check_cmd "mediagenda/api : le composant $_m19o_e11_c est inclus" test -n "$(_m19o_version_composant "$_m19o_e11_ci" "$_m19o_e11_c")"
done
check_cmd "mediagenda/api : .gitlab-ci.yml de 40 lignes au plus (hors commentaires et lignes vides)" \
  bash -c '[[ -n "$1" ]] && (( $(grep -cvE "^[[:space:]]*(#|$)" <<<"$1") <= 40 ))' _ "$_m19o_e11_ci"
check_cmd "mediagenda/api : aucune image « latest » ni privilège dans le .gitlab-ci.yml" \
  bash -c '[[ -n "$1" ]] && ! grep -qE ":latest\b|privileged|docker:dind" <<<"$1"' _ "$_m19o_e11_ci"

# Runners des jobs : k8s-par1 (ou, à partir de E24, k8s-par1-protege) ; jamais runner02.
_m19o_e11_runners() { # PROJET PIPELINE_JSON
  local id
  id="$(jq -r '.id // 0' <<<"${2:-null}" 2>/dev/null || echo 0)"
  _m19o_json "$(_m19o_jobs "$1" "$id")" \
    '[.[] | select(.runner != null) | .runner.description] | length >= 1 and all(test("^k8s-par1(-protege)?$"))'
}
_m19o_e11_main="$(_m19o_pipeline "$_M19O_P_API" "ref=main")"
check_cmd "mediagenda/api : le dernier pipeline de main a réussi" _m19o_json "$_m19o_e11_main" '.status == "success"'
check_cmd "mediagenda/api : tous ses jobs ont tourné sur les runners du cluster (k8s-par1)" _m19o_e11_runners "$_M19O_P_API" "$_m19o_e11_main"
_m19o_e11_tag="$(_m19o_pipeline_etiquette "$_M19O_P_API")"
check_cmd "mediagenda/api : le pipeline de la dernière étiquette vX.Y.Z a réussi" _m19o_json "$_m19o_e11_tag" '.status == "success"'
check_cmd "mediagenda/api : ses jobs ont tourné sur les runners du cluster" _m19o_e11_runners "$_M19O_P_API" "$_m19o_e11_tag"
check_cmd "mediagenda/api : le pipeline de l'étiquette contient image:publication et securite:signature réussis" \
  _m19o_json "$(_m19o_jobs "$_M19O_P_API" "$(jq -r '.id // 0' <<<"${_m19o_e11_tag:-null}" 2>/dev/null || echo 0)")" \
  '[.[] | select(.status == "success") | .name] | index("image:publication") != null and index("securite:signature") != null'

_m19o_e11_etq="$(jq -r '.ref // "absente"' <<<"${_m19o_e11_tag:-null}" 2>/dev/null || echo absente)"
check_cmd "Harbor : medisphere/mediagenda-api:$_m19o_e11_etq porte une signature Cosign" \
  bash -c 'jq -e "any(.accessories[]?; .type == \"signature.cosign\")" >/dev/null 2>&1 <<<"$1"' _ \
  "$(harbor_api "projects/medisphere/repositories/mediagenda-api/artifacts/$_m19o_e11_etq?with_accessory=true" 2>/dev/null || true)"
check_cmd "plateforme/medisphere (main) : docs/livraison/ci/normes-pipeline.md" \
  _m19o_fichier "$_M19O_P_DOC" docs/livraison/ci/normes-pipeline.md
