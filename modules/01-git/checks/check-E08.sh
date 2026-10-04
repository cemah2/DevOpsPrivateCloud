# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E08.sh — M01-E08 : annuler proprement (branches e08/* de formation/git-labo).
# Lancé depuis adm01. Lecture seule : API GitLab (jeton des checks) et ~/src/git-labo.

title "M01-E08 — Annuler proprement"
require_cmd curl jq

_m01_api="projects/formation%2Fgit-labo"
_m01_jq() {
  local desc="$1" filtre="$2" json="$3"; shift 3
  check_cmd "$desc" jq -e "$@" "$filtre" <<<"${json:-null}"
}
_m01_ref() { printf '%s' "${1//\//%2F}"; }
_m01_cmp() { gitlab_api "$_m01_api/repository/compare?from=main&to=$(_m01_ref "$1")" 2>/dev/null || true; }
# Chemin de fichier pour l'API : « / » et « . » encodés (sinon l'extension peut être mal interprétée)
_m01_fic() { local f="${1//\//%2F}"; printf '%s' "${f//./%2E}"; }
_m01_brut() { gitlab_api "$_m01_api/repository/files/$(_m01_fic "$1")/raw?ref=$(_m01_ref "$2")" 2>/dev/null; }

# --- Situations 1 à 3 : e08/travail ----------------------------------------------------------------
title "Situations 1 à 3 — e08/travail"
_m01_trav="$(_m01_cmp e08/travail)"
_m01_tip="$(gitlab_api "$_m01_api/repository/branches/$(_m01_ref e08/travail)" 2>/dev/null || true)"
_m01_fix="$(jq -r '.commit.parent_ids[0] // empty' <<<"${_m01_tip:-null}" 2>/dev/null)"
_m01_jq "e08/travail : deux commits de plus que main" '(.commits | length) == 2' "$_m01_trav"
_m01_jq "e08/travail : le dernier commit est un commit chore" '.commit.title | startswith("chore")' "$_m01_tip"
_m01_jq "e08/travail : l'avant-dernier est « fix: correction du filtre d'exclusion »" \
  '.title == "fix: correction du filtre d'"'"'exclusion"' \
  "$(gitlab_api "$_m01_api/repository/commits/${_m01_fix:-absent}" 2>/dev/null || true)"
_m01_jq "le commit fix contient conf/exclusions.conf et inventaire.sh" \
  '([.[].new_path] | index("conf/exclusions.conf") != null) and ([.[].new_path] | index("inventaire.sh") != null)' \
  "$(gitlab_api "$_m01_api/repository/commits/${_m01_fix:-absent}/diff" 2>/dev/null || true)"
check_cmd "e08/travail : .gitignore ignore secret.env" \
  bash -c 'grep -Eq "^/?secret\.env$" <<<"$1"' _ "$(_m01_brut .gitignore e08/travail)"
_m01_secret=0
for _m01_c in $(jq -r '.commits[]?.id' <<<"${_m01_trav:-null}" 2>/dev/null); do
  if gitlab_api "$_m01_api/repository/commits/$_m01_c/diff" 2>/dev/null \
     | jq -e 'any(.[]; .new_path == "secret.env" or .old_path == "secret.env")' >/dev/null 2>&1; then
    _m01_secret=1
  fi
done
check_cmd "secret.env n'apparaît dans aucun commit de e08/travail" test "$_m01_secret" -eq 0
check_cmd "README.md de e08/travail sans la ligne parasite" \
  bash -c '[ -n "$1" ] && ! grep -q "LIGNE AJOUTÉE PAR ERREUR" <<<"$1"' _ "$(_m01_brut README.md e08/travail)"
check_cmd "secret.env est toujours présent dans ~/src/git-labo" \
  test -f "${WB_SRC:-$HOME/src}/git-labo/secret.env"

# --- Situation 4 : e08/brouillon -------------------------------------------------------------------
title "Situation 4 — e08/brouillon"
_m01_br="$(_m01_cmp e08/brouillon)"
_m01_jq "e08/brouillon : un seul commit de plus que main" '(.commits | length) == 1' "$_m01_br"
_m01_jq "e08/brouillon : message propre (plus de « wip »)" \
  '.commits[0].title | test("^(wip|correction faute)"; "i") | not' "$_m01_br"
_m01_jq "e08/brouillon : contenu des trois commits d'origine (exclusions.txt et lib/format.sh)" \
  '([.diffs[].new_path] | index("exemples/exclusions.txt") != null) and ([.diffs[].new_path] | index("lib/format.sh") != null)' \
  "$_m01_br"
check_cmd "e08/brouillon : la faute de frappe corrigée est bien dans le contenu final" \
  bash -c 'grep -qx "template-debian13" <<<"$1"' _ "$(_m01_brut exemples/exclusions.txt e08/brouillon)"

# --- Situation 5 : e08/publiee ---------------------------------------------------------------------
title "Situation 5 — e08/publiee"
_m01_pub="$(_m01_cmp e08/publiee)"
_m01_jq "e08/publiee : les trois commits d'origine sont toujours là (pas de réécriture)" \
  '[.commits[].title] | (index("feat: rotation des exports") != null)
     and (index("feat: activer la purge automatique des exports") != null)
     and (index("docs: documenter la rotation") != null)' "$_m01_pub"
_m01_jq "e08/publiee : se termine par l'annulation (revert) de la purge automatique" \
  '.commit.title | startswith("Revert \"feat: activer la purge automatique des exports\"")' \
  "$(gitlab_api "$_m01_api/repository/branches/$(_m01_ref e08/publiee)" 2>/dev/null || true)"
check_cmd "e08/publiee : PURGE_AUTO n'est plus dans conf/inventaire.conf" \
  bash -c '[ -n "$1" ] && ! grep -q "^PURGE_AUTO=" <<<"$1"' _ "$(_m01_brut conf/inventaire.conf e08/publiee)"

# --- Situation 6 : e08/precieux --------------------------------------------------------------------
title "Situation 6 — e08/precieux"
_m01_jq "e08/precieux : les deux commits « travail précieux » sont récupérés et publiés" \
  '[.commits[].title] | (index("feat: travail précieux (1/2)") != null) and (index("feat: travail précieux (2/2)") != null)' \
  "$(_m01_cmp e08/precieux)"
