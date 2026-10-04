# shellcheck shell=bash
# shellcheck disable=SC2016  # variables jq entre apostrophes
#
# check-E21.sh — M01-E21 : revue de la merge request de Lucas (plateforme/medisphere, lucas/verif-certificats)
# Lancé depuis adm01. Lecture seule (API GitLab avec le jeton des checks).
# Le contrôle porte sur la forme de la revue (fils, commentaires sur les lignes, points majeurs vus) ;
# la qualité de fond s'évalue avec la grille du corrigé.

title "M01-E21 — Revue de la merge request d'un stagiaire"
require_cmd curl jq

_m01_p="projects/plateforme%2Fmedisphere"
_m01_moi="${WB_MOI:-}"
_m01_jq() { jq -e "$@" >/dev/null 2>&1; }

check_cmd "WB_MOI (ton compte GitLab) est renseigné dans lab/lab.env" test -n "$_m01_moi"

_m01_mr="$(gitlab_api "$_m01_p/merge_requests?source_branch=lucas%2Fverif-certificats&state=all&per_page=5" 2>/dev/null \
  | jq -c '[.[] | select(.author.username == "lucas.martin")][0] // empty' 2>/dev/null)" || _m01_mr=""
check_cmd "la MR de lucas.martin existe (ressources/M01-E21/creer-mr-lucas.sh)" test -n "$_m01_mr"

if [[ -n "$_m01_mr" && -n "$_m01_moi" ]]; then
  _m01_iid="$(jq -r .iid <<<"$_m01_mr")"
  check_cmd "la MR !$_m01_iid n'a pas été fusionnée en l'état" _m01_jq '.state != "merged"' <<<"$_m01_mr"

  _m01_d="$(gitlab_api "$_m01_p/merge_requests/$_m01_iid/discussions?per_page=100" 2>/dev/null)" || _m01_d="[]"
  _m01_mes="$(jq -c --arg u "$_m01_moi" '[.[].notes[] | select(.author.username == $u and (.system | not))]' <<<"$_m01_d" 2>/dev/null)" \
    || _m01_mes="[]"
  check_cmd "ta revue compte au moins 6 commentaires" _m01_jq 'length >= 6' <<<"$_m01_mes"
  check_cmd "au moins 4 commentaires sont posés sur des lignes précises du diff" \
    _m01_jq '[.[] | select(.position != null)] | length >= 4' <<<"$_m01_mes"
  check_cmd "un commentaire traite le jeton écrit en clair (secret exposé)" \
    _m01_jq 'any(.[]; .body | test("jeton|token|secret|glpat"; "i"))' <<<"$_m01_mes"
  check_cmd "un commentaire traite la vérification TLS désactivée" \
    _m01_jq 'any(.[]; .body | test("curl -k|--insecure|-k |TLS|certificat.*(v[ée]rif|valid)|v[ée]rif.*certificat"; "i"))' <<<"$_m01_mes"
  check_cmd "un commentaire traite les messages de commit" \
    _m01_jq 'any(.[]; .body | test("commit|conventional"; "i"))' <<<"$_m01_mes"
  check_cmd "un commentaire général (hors diff) donne la synthèse et la décision" \
    _m01_jq 'any(.[]; .position == null and (.body | length) >= 200)' <<<"$_m01_mes"
else
  skip "contenu de la revue" "MR ou WB_MOI absents"
fi
