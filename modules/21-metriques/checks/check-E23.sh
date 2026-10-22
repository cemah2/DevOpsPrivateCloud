# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions PromQL et filtres jq entre apostrophes
#
# check-E23.sh — M21-E23 : Diagnostiquer une saturation par les métriques
# À lancer depuis adm01. Lecture seule : GitLab (journal, tests), Prometheus du cluster, « kube ».

# shellcheck source=_m21-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-operationnel.sh"

title "M21-E23 — Diagnostiquer une saturation par les métriques"
require_cmd jq kubectl curl

_m21o_e23_journal="$(_m21o_arbre "$_M21O_P_DOC" docs/kubernetes/journal | grep -E 'INC-4823' | head -1 || true)"
check_cmd "journal INC-4823 dans docs/kubernetes/journal/ (plateforme/medisphere, main)" test -n "$_m21o_e23_journal"
_m21o_e23_mesures() {
  local n
  [[ -n "$_m21o_e23_journal" ]] || return 1
  n="$(_m21o_contenu "$_M21O_P_DOC" "$_m21o_e23_journal" | grep -Eo '[0-9]+([.,][0-9]+)? ?(ms|s|req/s|%)' | wc -l)"
  (( n >= 10 ))
}
check_cmd "le journal contient des mesures chiffrées (au moins dix valeurs avec unité)" _m21o_e23_mesures
check_output "le journal nomme une cause" '^#+ *Cause' _m21o_contenu "$_M21O_P_DOC" "${_m21o_e23_journal:-absent}"

_m21o_e23_r="$(_m21o_regles alert)"
_m21o_e23_alerte="$(jq -r '[.data.groups[].rules[] | select((.name | test("[Ss]atur|[Bb]rid|[Tt]hrottl")) and .labels.equipe == "mediagenda" and .health != "err") | .name][0] // empty' <<<"$_m21o_e23_r" 2>/dev/null || true)"
check_cmd "alerte de saturation de MédiAgenda chargée (${_m21o_e23_alerte:-aucune})" test -n "$_m21o_e23_alerte"
_m21o_e23_testee() {
  local f
  [[ -n "$_m21o_e23_alerte" ]] || return 1
  for f in $(_m21o_arbre "$_M21O_P_OBS" tests); do
    _m21o_contenu "$_M21O_P_OBS" "$f" | grep -q "alertname: *$_m21o_e23_alerte" && return 0
  done
  return 1
}
check_cmd "cette alerte a un test promtool sur main" _m21o_e23_testee
check_cmd "le job tests-regles du dernier pipeline de main a réussi" _m21o_job_ok "$_M21O_P_OBS" tests-regles

check_cmd "métriques de CloudNativePG collectées en recette (cnpg_*)" \
  _m21o_au_moins 'count({__name__=~"cnpg_.+", namespace="mediagenda-recette"})' 1
check_cmd "le Job de charge n'existe plus dans wb-essais" _m21o_json \
  "$(_m21o_k get jobs -n wb-essais -o json)" '[.items[] | select(.metadata.name == "charge-oha")] | length == 0'
