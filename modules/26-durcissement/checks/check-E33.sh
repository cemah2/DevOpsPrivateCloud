# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E33.sh — M26-E33 « Préparer la réponse à incident » (LIBRE)
# À lancer depuis adm01. Lecture seule : politique de cluster « quarantaine » (compte wb-checks),
# pods étiquetés en quarantaine, runbook RB-262 et compte rendu d'exercice sur table sur main.

# shellcheck source=_m26-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-production.sh"

title "M26-E33 — Préparer la réponse à incident"
require_cmd kubectl jq curl

title "Isolement préparé"
_m26_e33_q="$(_m26p_json get ciliumclusterwidenetworkpolicies quarantaine)"
check_cmd "la politique de cluster « quarantaine » existe et vise medisphere.internal/quarantaine=oui" _m26p_jq "$_m26_e33_q" \
  '(.spec.endpointSelector.matchLabels["medisphere.internal/quarantaine"] // "") == "oui"'
check_cmd "elle REFUSE (règles de refus, prioritaires sur les autorisations des équipes) en entrée et en sortie" _m26p_jq "$_m26_e33_q" \
  '((.spec.ingressDeny // []) | length) > 0 and ((.spec.egressDeny // []) | length) > 0'
check_cmd "aucune sortie possible : refus vers toutes les entités ou tous les réseaux" _m26p_jq "$_m26_e33_q" \
  'any(.spec.egressDeny[]; any(.toEntities[]?; . == "all") or any(.toCIDR[]?; . == "0.0.0.0/0"))'
check_cmd "aucun pod n'est resté en quarantaine après l'essai" _m26p_jq "$(_m26p_json get pods -A -l medisphere.internal/quarantaine=oui)" \
  '.items | length == 0'

title "Runbook et exercice"
check_cmd "$_M26P_DOC : RB-262 (isolement, collecte avec empreintes, preuves, obligations)" \
  _m26p_doc_present "$_M26P_DOC" docs/securite/durcissement/runbooks 'RB-262' 40 \
  'quarantaine' 'sha256|empreinte' 'preuves' '72'
check_cmd "$_M26P_DOC : compte rendu d'exercice sur table dans rapports/" \
  _m26p_doc_present "$_M26P_DOC" docs/securite/durcissement/rapports '(table|sur-table)' 15 'chronologie' 'action'
