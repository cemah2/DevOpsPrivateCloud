# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E32.sh — M19-E32 « Imposer le socle de sécurité à tous les projets »
# À lancer depuis adm01. Lecture seule, API de GitLab : planifications et pipelines de
# plateforme/outils, propriétaire et jetons du compte technique (sans valeurs), attributs des
# variables, tickets étiquetés conformite-ci.

# shellcheck source=_m19-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-production.sh"

title "M19-E32 — Socle de sécurité imposé à tous les projets"
require_cmd jq curl

_m19_e32_o="$(_m19p_p plateforme/outils)"
_m19_e32_s="$(_m19p_gl "projects/$_m19_e32_o/pipeline_schedules?scope=active&per_page=100" \
  | jq -c '[.[]? | select(.description | test("conformit"; "i"))] | first // null' 2>/dev/null || echo null)"
check_cmd "plateforme/outils : planification active du contrôle de conformité" _m19p_jq "$_m19_e32_s" '.active == true'
_m19_e32_proprio="$(jq -r '.owner.username // empty' <<<"$_m19_e32_s" 2>/dev/null || true)"
check_cmd "la planification n'appartient pas à un humain (compte technique : ${_m19_e32_proprio:-?})" bash -c \
  '[[ -n "$1" ]] && ! grep -qw -- "$1" <<<"$2"' _ "$_m19_e32_proprio" "$_M19P_HUMAINS"
_m19_e32_uid="$(jq -r '.owner.id // empty' <<<"$_m19_e32_s" 2>/dev/null || true)"
if [[ -n "$_m19_e32_uid" ]]; then
  check_cmd "jetons actifs du compte technique : tous avec une date d'expiration" _m19p_jq \
    "$(_m19p_gl "personal_access_tokens?user_id=$_m19_e32_uid&state=active&per_page=100")" \
    'length > 0 and all(.[]; .expires_at != null)'
fi
_m19_e32_pl="$(_m19p_gl "projects/$_m19_e32_o/pipelines?source=schedule&per_page=1" | jq -c '.[0] // null' 2>/dev/null || echo null)"
check_cmd "dernière exécution planifiée réussie il y a moins de 48 h" bash -c \
  'jq -e ".status == \"success\"" >/dev/null <<<"$1" && a="$(jq -r .updated_at <<<"$1")" && (( $(date +%s) - $(date -d "$a" +%s) < 172800 ))' _ "$_m19_e32_pl"
if [[ "$_m19_e32_pl" != null ]]; then
  check_cmd "elle a produit un rapport (artefacts du job de conformité)" _m19p_jq \
    "$(_m19p_jobs plateforme/outils "$(jq -r .id <<<"$_m19_e32_pl")")" \
    'any(.[]; (.name | test("conformit"; "i")) and .status == "success" and ((.artifacts // []) | any(.file_type == "archive")))'
fi
check_cmd "variable du jeton : protégée et masquée" _m19p_jq "$(_m19p_variables projects plateforme/outils)" \
  'any(.[]; (.key | test("CONFORMITE"; "i")) and (.key | test("TOKEN|JETON"; "i")) and .protected and .masked)'

title "Tickets"
check_output "legacy/legacy-rdv (non conforme) : un ticket conformite-ci ouvert" '^1$' _m19p_issues_ouvertes legacy/legacy-rdv conformite-ci
check_output "mediagenda/api (conforme) : aucun ticket conformite-ci ouvert" '^0$' _m19p_issues_ouvertes mediagenda/api conformite-ci

title "Documentation"
check_cmd "conformite.md sur main (règles, dérogations)" \
  _m19p_fichier_contient plateforme/medisphere docs/livraison/ci/conformite.md 'securite' 'd[ée]rogation'
