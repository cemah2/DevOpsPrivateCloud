# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E40.sh — M21-E40 « Panne : l'alerte sonne sans arrêt » : aucune route ne relance plus d'une fois
# par heure ni ne regroupe par pod (ou pas du tout), la règle témoin attend avant de sonner, la boîte de
# l'astreinte n'est pas inondée, RB-218, panne close. Lecture seule.

# shellcheck source=_m21-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-expert.sh"

title "M21-E40 — Un problème, un courriel"
require_cmd jq yq kubectl curl

_m21_e40_conf="$(_m21x_am_config_json)" || _m21_e40_conf=""
if [[ -z "$_m21_e40_conf" ]]; then
  skip "configuration d'Alertmanager" "API de 10.10.41.61 muette (lab/bin/check 21 06)"
else
  check_cmd "aucune route ne relance plus souvent qu'une fois par heure (repeat_interval ≥ 1h)" \
    jq -e "$_M21X_JQ_SECONDES"' [.route | .. | objects | .repeat_interval? // empty | select(secondes < 3600)] | length == 0' <<<"$_m21_e40_conf"
  check_cmd "aucune route ne regroupe par pod ni ne supprime le regroupement (« ... »)" \
    jq -e '[.route | .. | objects | .group_by? // empty | .[] | select(. == "pod" or . == "...")] | length == 0' <<<"$_m21_e40_conf"
fi
if _m21x_temoins; then
  check_cmd "règle témoin TemoinFileAttenteHaute : un « for » d'au moins une minute" \
    _m21x_kq "$_M21X_JQ_SECONDES"' [.spec.groups[].rules[] | select(.alert == "TemoinFileAttenteHaute") | (.for // "0s") | secondes] | length >= 1 and all(. >= 60)' \
    -n wb-pannes prometheusrules.monitoring.coreos.com temoin-metriques
else
  skip "règle témoin" "absente : elle est créée à la première injection (lab/bin/break 21 40)"
fi
check_cmd "boîte astreinte@ : au plus 4 courriels TemoinFileAttenteHaute dans les 30 dernières minutes" \
  bash -c '[[ -n "$1" && "$1" -le 4 ]]' _ "$(_m21x_courriels 'to:astreinte@medisphere.internal TemoinFileAttenteHaute' "$(($(date +%s) - 1800))")"
check_cmd "RB-218 : section « trop de courriels »" \
  _m21x_doc_contient "$_m21x_rb/RB-218-*.md" '^#+ .*(trop|bavard|sans arr|tempête|inond)'
check_cmd "panne M21-E40 close (lab/bin/break 21 40 --annuler après réparation)" _m21x_aucune_panne_active E40
