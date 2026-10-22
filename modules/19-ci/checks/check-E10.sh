# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E10.sh — M19-E10 : Des gabarits aux composants CI/CD
# À lancer depuis adm01. Lecture seule : API GitLab (fichiers sur main, releases, pipelines),
# GraphQL (catalogue CI/CD : requête de lecture), journal local.

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E10 — Des gabarits aux composants CI/CD"
require_cmd jq yq curl

# Absence d'un fichier : 404 (et non « erreur quelconque », qui passerait si GitLab est injoignable).
_m19o_e10_absent() { [[ "$(_m19o_code "$1/repository/files/$(_m19o_uri "$2")?ref=main")" == 404 ]]; }

for _m19o_e10_c in qualite construction-image securite deploiement release; do
  _m19o_e10_t="$(_m19o_contenu "$_M19O_P_TPL" "templates/$_m19o_e10_c/template.yml")"
  check_cmd "ci-templates (main) : templates/$_m19o_e10_c/template.yml avec un en-tête spec:inputs" \
    bash -c 'yq -e "select(document_index == 0) | .spec.inputs | length > 0" <<<"$1" >/dev/null 2>&1' _ "$_m19o_e10_t"
  # GitLab cherche templates/<nom>.yml AVANT templates/<nom>/template.yml : un gabarit v1 laissé en
  # place masquerait le composant.
  check_cmd "ci-templates (main) : aucun templates/$_m19o_e10_c.yml ne masque le composant" \
    _m19o_e10_absent "$_M19O_P_TPL" "templates/$_m19o_e10_c.yml"
done
check_output "ci-templates (main) : README.md à la racine avec une section « Composants »" '^## +Composants' \
  _m19o_contenu "$_M19O_P_TPL" README.md
check_cmd "ci-templates : la release v2.0.0 existe" gitlab_api "$_M19O_P_TPL/releases/v2.0.0"

_m19o_e10_cat="$(_m19o_graphql '{ ciCatalogResource(fullPath: "plateforme/ci-templates") { name versions(first: 50) { nodes { name } } } }')"
check_cmd "catalogue CI/CD : plateforme/ci-templates est publié et contient la version 2.0.0" \
  _m19o_json "$_m19o_e10_cat" '[.data.ciCatalogResource.versions.nodes[]?.name | select(test("^v?2\\.0\\.0$"))] | length == 1'

_m19o_e10_ci="$(_m19o_contenu "$_M19O_P_LABO" .gitlab-ci.yml)"
check_cmd "formation/ci-labo (main) : .gitlab-ci.yml n'inclut que des composants de plateforme/ci-templates en v2.x.y épinglée" \
  _m19o_que_des_composants "$_m19o_e10_ci"
_m19o_e10_p="$(_m19o_pipeline "$_M19O_P_LABO" "ref=main")"
_m19o_e10_id="$(jq -r '.id // 0' <<<"${_m19o_e10_p:-null}" 2>/dev/null || echo 0)"
check_cmd "formation/ci-labo : le dernier pipeline de main a réussi" _m19o_json "$_m19o_e10_p" '.status == "success"'
check_cmd "formation/ci-labo : ce pipeline contient les jobs du composant qualite (qualite:lint, qualite:tests)" \
  _m19o_json "$(_m19o_jobs "$_M19O_P_LABO" "$_m19o_e10_id")" \
  '[.[].name] | index("qualite:lint") != null and index("qualite:tests") != null'
check_output "journal ~/m19/e10/journal.md (entrées, versions @v2.0.0 / @2 / @~latest)" '~latest|@2\b|catalogue' \
  cat "$_M19O_TRAVAIL/e10/journal.md"
