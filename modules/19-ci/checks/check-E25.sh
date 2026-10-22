# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E25.sh — M19-E25 « Secrets en CI : variables protégées, CI_JOB_TOKEN, jetons d'identité »
# À lancer depuis adm01. Lecture seule, API de GitLab : attributs des variables (les valeurs sont
# retirées dès la réception, jamais affichées), portée du CI_JOB_TOKEN, jetons de projet, jobs.

# shellcheck source=_m19-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-production.sh"

title "M19-E25 — Secrets en CI"
require_cmd jq curl

# Clé de secret : TOKEN, PASSWORD, KEY, SECRET ; identités de lecture (*_RO_*) : masquées suffisent.
# Exception écrite de E24 (jusqu'au mini-projet E46) : COSIGN_PRIVATE_KEY de groupe, type fichier et
# protégée, que GitLab ne peut pas masquer (clé PEM multiligne, M13-E07).
_m19_e25_filtre='if type != "array" then "illisible" else [.[] | select((.key | ascii_upcase | test("TOKEN|PASSWORD|PASSWD|SECRET|(^|_)KEY($|_)"))
  and ((.key == "COSIGN_PRIVATE_KEY" and .variable_type == "file" and .protected) | not)
  and ((.masked | not) or ((.protected | not) and (.key | test("_RO_") | not))))] | map(.key) end'

title "Variables des groupes et de leurs projets"
for _m19_e25_g in plateforme mediagenda medidoc; do
  _m19_e25_v="$(_m19p_variables groups "$_m19_e25_g")"
  check_output "groupe $_m19_e25_g : secrets tous protégés et masqués" '^\[\]$' jq -c "$_m19_e25_filtre" <<<"$_m19_e25_v"
  while read -r _m19_e25_p; do
    [[ -n "$_m19_e25_p" ]] || continue
    _m19_e25_v="$(_m19p_variables projects "$_m19_e25_p")"
    check_output "$_m19_e25_p : secrets tous protégés et masqués" '^\[\]$' jq -c "$_m19_e25_filtre" <<<"$_m19_e25_v"
    check_cmd "$_m19_e25_p : liste d'autorisation du CI_JOB_TOKEN active" \
      _m19p_jq "$(_m19p_gl "projects/$(_m19p_p "$_m19_e25_p")/job_token_scope")" '.inbound_enabled == true'
  done < <(_m19p_gl "groups/$_m19_e25_g/projects?include_subgroups=true&archived=false&per_page=100" | jq -r '.[]?.path_with_namespace' 2>/dev/null || true)
done
check_cmd "mediagenda/api : DEPLOIEMENT_TOKEN cachée, protégée, de portée promotion/*" \
  _m19p_jq "$(_m19p_variables projects mediagenda/api)" \
  'any(.[]; .key == "DEPLOIEMENT_TOKEN" and .hidden == true and .protected and .environment_scope == "promotion/*")'

title "Jeton de promotion"
_m19_e25_t="$(_m19p_gl "projects/$(_m19p_p mediagenda/deploiement)/access_tokens?per_page=100" \
  | jq -c '[.[]? | select(.name == "ci-promotion" and .active and (.revoked | not))] | sort_by(.created_at) | last // null' 2>/dev/null || echo null)"
check_cmd "jeton de projet ci-promotion actif" test "$_m19_e25_t" != null
check_cmd "ci-promotion expire dans moins d'un an" bash -c \
  'e="$(jq -r ".expires_at // empty" <<<"$1")"; [[ -n "$e" ]] && (( $(date -d "$e" +%s) - $(date +%s) < 366*86400 ))' _ "$_m19_e25_t"
_m19_e25_cree="$(jq -r '.created_at // empty' <<<"$_m19_e25_t" 2>/dev/null || true)"
check_cmd "ci-promotion tourné il y a moins de 60 jours" bash -c \
  '[[ -n "$1" ]] && (( $(date +%s) - $(date -d "$1" +%s) < 60*86400 ))' _ "$_m19_e25_cree"
_m19_e25_pl="$(_m19p_pipeline_etiquette mediagenda/api)"
check_cmd "dernier pipeline d'étiquette de mediagenda/api réussi APRÈS la rotation" bash -c \
  'jq -e --arg c "$2" ".status == \"success\" and (\$c != \"\") and (.created_at > \$c)" >/dev/null <<<"$1"' _ "$_m19_e25_pl" "$_m19_e25_cree"

title "Jeton d'identité"
check_cmd "formation/ci-labo : job jeton-identite réussi" _m19p_jq \
  "$(_m19p_gl "projects/$(_m19p_p formation/ci-labo)/jobs?scope%5B%5D=success&per_page=100")" 'any(.[]; .name == "jeton-identite")'

title "Code et documentation"
check_cmd "plateforme/outils : bin/ci-inventaire-variables.sh sur main (sans valeurs : del(.value))" \
  _m19p_fichier_contient plateforme/outils bin/ci-inventaire-variables.sh 'del\(\.value\)'
check_cmd "secrets-ci.md sur main (CI_JOB_TOKEN, revendications OIDC, rotation)" \
  _m19p_fichier_contient plateforme/medisphere docs/livraison/ci/secrets-ci.md 'CI_JOB_TOKEN' 'ref_protected' 'rotation'
check_cmd "RB-191 sur main (docs/livraison/ci/runbooks/)" _m19p_doc_prefixe plateforme/medisphere docs/livraison/ci/runbooks RB-191 'ci-promotion' 'rotat'
