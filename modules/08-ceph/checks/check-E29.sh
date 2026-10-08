# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E29.sh — M08-E29 « Régler la mémoire, la récupération et mClock »
# Lecture seule : configuration centrale (config dump/get), valeurs en vigueur par OSD (config show),
# drapeaux de l'osdmap (osd dump), hôtes de l'orchestrateur, santé, documentation (API GitLab).

# shellcheck source=_m08-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-production.sh"

title "M08-E29 — Régler la mémoire, la récupération et mClock"
require_cmd jq curl
_m08p_charger
check_cmd "le cluster répond depuis $_M08P_ADMIN (ceph status)" _m08p_joignable

title "Mémoire des OSD"
check_cmd "osd_memory_target = 1 Gio posé au niveau « osd » de la configuration centrale" \
  _m08p_config_valeur osd osd_memory_target "$_M08P_MEM_OSD"
check_output "réglage automatique de cephadm désactivé pour les OSD" '^false$' \
  _m08p_config_get osd osd_memory_target_autotune
check_cmd "aucune valeur résiduelle de osd_memory_target par hôte ou par OSD (masque, osd.N)" \
  _m08p_jq _M08P_CONFIG '[.[] | select(.name == "osd_memory_target" and ((.section | test("^osd\\.[0-9]+$")) or ((.mask // "") != "")))] | length == 0'
_m08_e29_ids="$(_m08p_osd_ids 2>/dev/null || true)"
check_output "au moins neuf OSD dans la carte" '^(9|[1-9][0-9])$' bash -c 'grep -c . <<<"$1"' _ "$_m08_e29_ids"
_m08_e29_mem_ko=""
[[ -n "$_m08_e29_ids" ]] || _m08_e29_mem_ko=" (aucun OSD lu)"
while read -r _m08_e29_i; do
  [[ -n "$_m08_e29_i" ]] || continue
  [[ "$(_m08p_config_show "osd.$_m08_e29_i" osd_memory_target 2>/dev/null || true)" == "$_M08P_MEM_OSD" ]] \
    || _m08_e29_mem_ko+=" osd.$_m08_e29_i"
done <<<"$_m08_e29_ids"
check_output "osd_memory_target en vigueur = 1 Gio sur chaque OSD${_m08_e29_mem_ko:+ (écart :$_m08_e29_mem_ko)}" '^$' \
  echo "$_m08_e29_mem_ko"

title "mClock et récupération"
check_cmd "aucun réglage mClock ou de récupération posé sur un OSD particulier" \
  _m08p_jq _M08P_CONFIG '[.[] | select((.section | test("^osd\\.[0-9]+$")) and (.name | test("^(osd_mclock_|osd_max_backfills|osd_recovery_max_active|osd_recovery_sleep|osd_op_queue)")))] | length == 0'
check_output "osd_mclock_override_recovery_settings n'est pas activé" '^false$' \
  _m08p_config_get osd osd_mclock_override_recovery_settings
check_output "profil mClock en vigueur sur un OSD : profil intégré (balanced ou high_client_ops)" \
  '^(balanced|high_client_ops)$' _m08p_config_show "osd.$(head -n 1 <<<"$_m08_e29_ids")" osd_mclock_profile
check_cmd "osd_max_backfills / osd_recovery_max_active non posés au niveau « osd » ou « global »" \
  _m08p_jq _M08P_CONFIG '[.[] | select((.section == "osd" or .section == "global") and (.name | test("^(osd_max_backfills|osd_recovery_max_active)")))] | length == 0'

title "Retour au nominal"
_m08_e29_dump="$(_m08p_json 'osd dump')"
check_cmd "aucun drapeau global noout, norebalance, nobackfill, norecover, pause" bash -c \
  'jq -e "(.flags // \"\") | test(\"noout|norebalance|nobackfill|norecover|pause\") | not" >/dev/null <<<"$1"' _ "$_m08_e29_dump"
check_cmd "aucun drapeau posé sur un OSD, un hôte ou une classe (add-noout, set-group)" bash -c \
  'jq -e "((.crush_node_flags // {}) | length == 0) and ((.device_class_flags // {}) | length == 0)
          and all(.osds[]?; (.state // []) | index(\"noout\") | not)" >/dev/null <<<"$1"' _ "$_m08_e29_dump"
check_cmd "aucun hôte en maintenance ni hors ligne" _m08p_jq _M08P_HOTES 'length >= 3 and all(.[]; (.status // "") == "")'
check_cmd "le cluster est HEALTH_OK" _m08p_sante_ok

title "Documentation"
check_cmd "performances.md : budget mémoire et récupération par profil mClock" \
  _m08p_doc_main docs/stockage/performances.md 'osd_memory_target' 'high_recovery_ops' 'high_client_ops'
