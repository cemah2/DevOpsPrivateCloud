# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E06.sh — M27-E06 : migrations sans interruption (expand/contract)
# À lancer depuis adm01. Lecture seule : fichiers et jobs CI de mediagenda/api (GitLab), journal du
# Job mediagenda-migrations en recette et en prod (fin de « flyway info »), documentation.

# shellcheck source=_m27-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-operationnel.sh"

title "M27-E06 — Migrations sans interruption : expand/contract"
require_cmd jq kubectl curl

# --- 1. Les migrations -----------------------------------------------------------------------------------
_m27o_e06_arbre="$(gitlab_api "$_M27D_P_API/repository/tree?ref=main&path=migrations&per_page=100" 2>/dev/null || true)"
_m27o_e06_v3="$(jq -r '[.[].name | select(test("^V3__.*\\.sql$"))] | first // empty' <<<"${_m27o_e06_arbre:-[]}" 2>/dev/null || true)"
_m27o_e06_v4="$(jq -r '[.[].name | select(test("^V4__.*\\.sql$"))] | first // empty' <<<"${_m27o_e06_arbre:-[]}" 2>/dev/null || true)"
if [[ -z "$_m27o_e06_v3" ]]; then
  _ko "mediagenda/api (main) : migration V3__… (expand) absente de migrations/"
else
  _m27o_e06_c3="$(_m27d_contenu_main "$_M27D_P_API" "migrations/$_m27o_e06_v3")"
  check_cmd "V3 ($_m27o_e06_v3) : délai de verrou posé (SET LOCAL lock_timeout)" bash -c \
    'grep -Eiq "^[[:space:]]*SET[[:space:]]+LOCAL[[:space:]]+lock_timeout" <<<"$1"' _ "$_m27o_e06_c3"
  check_cmd "V3 : ajout compatible (ADD COLUMN, contraintes NOT VALID, aucun DROP)" bash -c \
    'grep -Eiq "ADD[[:space:]]+COLUMN" <<<"$1" && grep -Eiq "NOT[[:space:]]+VALID" <<<"$1" && ! grep -Eiq "^[^-]*\bDROP\b" <<<"$1"' _ "$_m27o_e06_c3"
fi
if [[ -z "$_m27o_e06_v4" ]]; then
  _ko "mediagenda/api (main) : migration V4__… (contract) absente (à livrer avec la version SUIVANTE)"
else
  check_output "V4 ($_m27o_e06_v4) : contraintes validées (VALIDATE CONSTRAINT)" '[Vv][Aa][Ll][Ii][Dd][Aa][Tt][Ee][[:space:]]+[Cc][Oo][Nn][Ss][Tt][Rr][Aa][Ii][Nn][Tt]' \
    _m27d_contenu_main "$_M27D_P_API" "migrations/$_m27o_e06_v4"
fi

# --- 2. Le garde-fou de la CI ------------------------------------------------------------------------------
check_cmd "mediagenda/api : le job migrations:compatibilite a réussi sur main" \
  _m27o_job_reussi "$_M27D_P_API" "migrations:compatibilite"

# --- 3. Appliquées en recette et en prod ----------------------------------------------------------------------
for _m27o_e06_env in "$_M27D_ENV_RECETTE" "$_M27D_ENV_PROD"; do
  _m27o_e06_log="$(_m27o_journal_job "mediagenda-${_m27o_e06_env}" mediagenda-migrations)"
  if [[ -z "$_m27o_e06_log" ]]; then
    skip "$_m27o_e06_env : versions 3 et 4 appliquées" "aucun pod réussi du Job mediagenda-migrations encore présent ; relance une synchronisation"
    continue
  fi
  check_cmd "$_m27o_e06_env : versions 3 et 4 appliquées (flyway info : Success)" bash -c '
    grep -Eq "^\| Versioned \| 3 +\|.*\| Success +\|" <<<"$1" && grep -Eq "^\| Versioned \| 4 +\|.*\| Success +\|" <<<"$1"' _ "$_m27o_e06_log"
done

# --- 4. Documentation ---------------------------------------------------------------------------------------
check_cmd "plateforme/medisphere (main) : ${_M27D_DOC}/migrations.md décrit expand/contract" \
  _m27d_doc_contient "${_M27D_DOC}/migrations.md" 'expand'
check_cmd "migrations.md : lock_timeout documenté" _m27d_doc_contient "${_M27D_DOC}/migrations.md" 'lock_timeout'
