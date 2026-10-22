# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E23.sh — M19-E23 : Accélérer un pipeline lent
# À lancer depuis adm01. Lecture seule : API GitLab (fichiers, pipelines de MR, composant inclus).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E23 — Accélérer un pipeline lent"
require_cmd jq yq curl

_m19o_e23_doc="$(_m19o_contenu "$_M19O_P_DOC" docs/livraison/ci/mesures-pipeline.md)"
check_cmd "plateforme/medisphere (main) : docs/livraison/ci/mesures-pipeline.md" test -n "$_m19o_e23_doc"
_m19o_e23_seuil="$(grep -oE '^Seuil : [0-9]+ s' <<<"$_m19o_e23_doc" | grep -oE '[0-9]+' | head -n 1 || true)"
check_cmd "le livrable contient la ligne « Seuil : <N> s » (lu : ${_m19o_e23_seuil:-absent})" test -n "$_m19o_e23_seuil"
check_cmd "le livrable contient le tableau des leviers (référence, gain, décision)" \
  bash -c 'grep -qiE "^\|.*levier.*\|" <<<"$1" && grep -qiE "r(é|e)f(é|e)rence" <<<"$1"' _ "$_m19o_e23_doc"

# Médiane des durées des 3 derniers pipelines de MR RÉUSSIS de mediagenda/api.
_m19o_e23_durees="$(_m19o_api "$_M19O_P_API/pipelines?source=merge_request_event&status=success&order_by=id&sort=desc&per_page=3" \
  | jq -r '.[].id' 2>/dev/null | while read -r id; do
      _m19o_api "$_M19O_P_API/pipelines/$id" | jq -r '.duration // empty | floor' 2>/dev/null || true
    done || true)"
_m19o_e23_n="$(grep -c . <<<"$_m19o_e23_durees" || true)"
_m19o_e23_med="$(_m19o_mediane <<<"$_m19o_e23_durees")"
check_cmd "mediagenda/api : 3 pipelines de MR réussis mesurables (trouvés : ${_m19o_e23_n:-0})" test "${_m19o_e23_n:-0}" -ge 3
check_cmd "médiane des 3 derniers pipelines de MR (${_m19o_e23_med:-?} s) ≤ seuil (${_m19o_e23_seuil:-?} s)" \
  bash -c '[[ -n "$1" && -n "$2" ]] && (( $1 <= $2 ))' _ "$_m19o_e23_med" "$_m19o_e23_seuil"
# Le seuil doit représenter un vrai gain : au plus 0,6 × la référence écrite dans le livrable (« 545 s »
# dans la ligne « Durée du pipeline » du tableau de référence), si elle y figure.
_m19o_e23_ref="$(grep -iE '^\| *Durée du pipeline *\|' <<<"$_m19o_e23_doc" | grep -oE '[0-9]+ s' | grep -oE '[0-9]+' | head -n 1 || true)"
if [[ -n "$_m19o_e23_ref" ]]; then
  check_cmd "le seuil vaut au plus 60 % de la référence (${_m19o_e23_ref} s)" \
    bash -c '(( $1 * 10 <= $2 * 6 ))' _ "$_m19o_e23_seuil" "$_m19o_e23_ref"
else
  skip "seuil ≤ 60 % de la référence" "ligne « | Durée du pipeline | <N> s | » absente du livrable"
fi

# Clé de cache des jobs Python calculée sur uv.lock, dans la version du composant qualite incluse.
_m19o_e23_ci="$(_m19o_contenu "$_M19O_P_API" .gitlab-ci.yml)"
_m19o_e23_v="$(_m19o_version_composant "$_m19o_e23_ci" qualite)"
_m19o_e23_tpl="$(_m19o_contenu "$_M19O_P_TPL" templates/qualite/template.yml "${_m19o_e23_v:-main}")"
check_cmd "composant qualite ${_m19o_e23_v:-?} : clé de cache calculée sur uv.lock (cache:key:files)" \
  bash -c 'yq -e "select(document_index == 1) | [.. | select(tag == \"!!map\" and has(\"files\")) | .files[] | select(test(\"uv\\.lock\"))] | length >= 1" <<<"$1" >/dev/null 2>&1' _ "$_m19o_e23_tpl"
