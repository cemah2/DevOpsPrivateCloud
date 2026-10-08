# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M08-E37 « Panne : plus aucune écriture » : seuils de remplissage cohérents, aucun
# OSD ni pool plein, quota de rbd-test non saturé, aucun drapeau pause/noout. Lecture seule.

# shellcheck source=_m08-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-expert.sh"

title "M08-E37 — Les écritures passent"
require_cmd jq ssh

if _m08x_cluster_repond; then
  check_cmd "full_ratio entre 0,90 et 0,97" _m08x_jq '.osd.full_ratio >= 0.90 and .osd.full_ratio <= 0.97'
  check_cmd "seuils ordonnés : nearfull < backfillfull < full" \
    _m08x_jq '.osd.nearfull_ratio < .osd.backfillfull_ratio and .osd.backfillfull_ratio < .osd.full_ratio and .osd.nearfull_ratio >= 0.75'
  check_cmd "aucun OSD plein ou presque plein (OSD_FULL, OSD_NEARFULL, OSD_BACKFILLFULL)" \
    _m08x_jq '.health.checks | (has("OSD_FULL") or has("OSD_NEARFULL") or has("OSD_BACKFILLFULL")) | not'
  check_cmd "aucun pool plein ou presque plein (POOL_FULL, POOL_NEAR_FULL)" \
    _m08x_jq '.health.checks | (has("POOL_FULL") or has("POOL_NEAR_FULL")) | not'
  check_cmd "quota de rbd-test absent ou supérieur à 1 Gio" \
    _m08x_jq '.quota.quota_max_bytes == 0 or .quota.quota_max_bytes > 1073741824'
  check_cmd "aucun drapeau pause (pauserd/pausewr) ni full" \
    _m08x_jq '.osd.flags | split(",") | map(select(. == "pauserd" or . == "pausewr" or . == "full")) | length == 0'
  check_cmd "aucun drapeau noout oublié" _m08x_jq '.osd.flags | split(",") | index("noout") | not'
else
  skip "seuils et drapeaux" "les moniteurs ne répondent pas au nœud $_m08x_admin"
fi
check_cmd "panne M08-E37 close (lab/bin/break 08 37 --annuler après réparation)" _m08x_aucune_panne_active E37
