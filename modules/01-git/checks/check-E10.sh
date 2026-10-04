# shellcheck shell=bash
#
# check-E10.sh — M01-E10 : le cycle d'une merge request (plateforme/medisphere, branche docs/fiche-forge)
# Lancé depuis adm01. Lecture seule (API GitLab avec le jeton des checks).

title "M01-E10 — Le cycle d'une merge request"
require_cmd curl jq

_m01_p="projects/plateforme%2Fmedisphere"
_m01_jq() { jq -e "$1" <<<"$2" >/dev/null 2>&1; }
# _m01_code CHEMIN — code HTTP d'un GET sur l'API (jeton des checks)
_m01_code() {
  local f="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
  [[ -r "$f" ]] || { echo 000; return; }
  curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<"$f")") \
    "${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4/$1" 2>/dev/null || true
}

_m01_mr="$(gitlab_api "$_m01_p/merge_requests?source_branch=docs%2Ffiche-forge&state=merged&per_page=5" 2>/dev/null \
  | jq -c '.[0] // empty' 2>/dev/null)" || _m01_mr=""
check_cmd "une MR depuis docs/fiche-forge est fusionnée dans plateforme/medisphere" test -n "$_m01_mr"

if [[ -n "$_m01_mr" ]]; then
  _m01_iid="$(jq -r .iid <<<"$_m01_mr")"
  check_cmd "la MR !$_m01_iid a une description (contexte, contenu, vérifications)" \
    _m01_jq '(.description // "") | length >= 80' "$_m01_mr"

  _m01_disc="$(gitlab_api "$_m01_p/merge_requests/$_m01_iid/discussions?per_page=100" 2>/dev/null)" || _m01_disc="[]"
  check_cmd "karim.benali a relu la MR (fils de discussion présents)" \
    _m01_jq '[.[].notes[] | select(.author.username == "karim.benali")] | length >= 3' "$_m01_disc"
  check_cmd "tu as répondu dans les fils de Karim" \
    _m01_jq '[.[] | select(any(.notes[]; .author.username == "karim.benali"))
              | select(any(.notes[]; .author.username != "karim.benali" and (.system | not)))] | length >= 1' "$_m01_disc"
  check_cmd "tous les fils de discussion sont résolus" \
    _m01_jq '[.[].notes[] | select(.resolvable and (.resolved | not))] | length == 0' "$_m01_disc"

  _m01_appr="$(gitlab_api "$_m01_p/merge_requests/$_m01_iid/approvals" 2>/dev/null)" || _m01_appr="{}"
  check_cmd "la MR a été approuvée par karim.benali avant fusion" \
    _m01_jq 'any(.approved_by[]?; .user.username == "karim.benali")' "$_m01_appr"
else
  skip "relecture, approbation et description de la MR" "pas de MR fusionnée"
fi

_m01_fiche="$(gitlab_api "$_m01_p/repository/files/docs%2Fsocle%2Fforge.md/raw?ref=main" 2>/dev/null)" || _m01_fiche=""
check_cmd "docs/socle/forge.md existe sur main" test -n "$_m01_fiche"
check_cmd "forge.md : la suggestion de titre de Karim est appliquée" \
  test "$(head -n 1 <<<"$_m01_fiche")" = "# Fiche de service — forge GitLab (git01)"
check_cmd "forge.md : l'URL de la forge y figure" grep -q 'git01\.par1\.medisphere\.internal' <<<"$_m01_fiche"
check_cmd "forge.md : une section traite l'indisponibilité de la forge" grep -qiE 'indisponib' <<<"$_m01_fiche"
check_cmd "la branche docs/fiche-forge a été supprimée après la fusion" \
  test "$(_m01_code "$_m01_p/repository/branches/docs%2Ffiche-forge")" = 404
