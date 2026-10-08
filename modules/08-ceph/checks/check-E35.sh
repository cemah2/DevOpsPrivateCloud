# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E35.sh — M08-E35 « Panne : un OSD a disparu » : tous les OSD sont up et in, aucun démon
# masqué ou en échec, aucun disque hors ligne côté invité, aucun drapeau de maintenance oublié.
# Lecture seule.

# shellcheck source=_m08-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-expert.sh"

title "M08-E35 — Tous les OSD sont en service"
require_cmd jq ssh

if _m08x_cluster_repond; then
  check_cmd "au moins 9 OSD déclarés" _m08x_jq '.status.osdmap.num_osds >= 9'
  check_cmd "tous les OSD sont « up »" _m08x_jq '.status.osdmap.num_osds == .status.osdmap.num_up_osds'
  check_cmd "tous les OSD sont « in » (aucun écarté du placement)" _m08x_jq '.status.osdmap.num_osds == .status.osdmap.num_in_osds'
  check_cmd "aucun OSD avec un poids de reweight nul" _m08x_jq '[.osd.osds[] | select(.weight == 0)] | length == 0'
  check_cmd "aucun drapeau noout/noup/noin/nodown laissé posé" \
    _m08x_jq '.osd.flags | split(",") | map(select(. == "noout" or . == "noup" or . == "noin" or . == "nodown")) | length == 0'
  check_cmd "santé sans OSD_DOWN ni PG dégradé" _m08x_jq '.health.checks | (has("OSD_DOWN") or has("PG_DEGRADED") or has("OSD_HOST_DOWN")) | not'
else
  skip "état des OSD" "les moniteurs ne répondent pas au nœud $_m08x_admin"
fi
for _m08_e35_h in "${_m08x_noeuds[@]}"; do
  check_ssh "$_m08_e35_h : aucune unité ceph masquée ou en échec" "$_m08_e35_h" "sudo -n bash -c $(printf '%q' "$_m08x_cmd_unites_saines")"
  check_ssh "$_m08_e35_h : tous les disques SCSI en état « running »" "$_m08_e35_h" \
    '! grep -vqx running /sys/block/sd*/device/state 2>/dev/null'
done
check_cmd "panne M08-E35 close (lab/bin/break 08 35 --annuler après réparation)" _m08x_aucune_panne_active E35
