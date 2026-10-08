# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes et filtres entre apostrophes (hôte distant, jq)
# check-E41.sh — M08-E41 « Panne : le montage CephFS est figé » : un MDS actif et au moins un en
# attente, droits de client.sonde-fs sur la racine, montage du client présent et réactif. Lecture seule.

# shellcheck source=_m08-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-expert.sh"

title "M08-E41 — Le CephFS répond"
require_cmd jq ssh

if _m08x_cluster_repond; then
  check_cmd "cephfs : un MDS actif" _m08x_jq '[.fs.mdsmap.info[] | select(.state == "up:active")] | length >= 1'
  check_cmd "cephfs : standby_count_wanted ≥ 1" _m08x_jq '.fs.mdsmap.standby_count_wanted >= 1'
  check_cmd "au moins un MDS en attente (standby) disponible" \
    _m08x_jq '([.orch[] | select(.type == "mds")] | length) > ([.fs.mdsmap.info[]] | length)'
  check_cmd "santé sans FS_DEGRADED, MDS_ALL_DOWN ni MDS_INSUFFICIENT_STANDBY" \
    _m08x_jq '.health.checks | (has("FS_DEGRADED") or has("MDS_ALL_DOWN") or has("MDS_INSUFFICIENT_STANDBY") or has("FS_WITH_FAILED_MDS")) | not'
  if _m08x_temoins; then
    check_cmd "client.sonde-fs : droits MDS en lecture-écriture sans restriction de chemin" \
      _m08x_jq '.sondefs.mds | (test("allow rw") and (test("path=/[^ ,]") | not))'
  fi
else
  skip "état des MDS" "les moniteurs ne répondent pas au nœud $_m08x_admin"
fi
for _m08_e41_h in "${_m08x_noeuds[@]}"; do
  check_ssh "$_m08_e41_h : aucune unité ceph masquée ou en échec" "$_m08_e41_h" "sudo -n bash -c $(printf '%q' "$_m08x_cmd_unites_saines")"
done
if _m08x_temoins; then
  check_ssh "$_m08x_client : /mnt/sonde-fs est un montage ceph" "$_m08x_client" \
    '[ "$(findmnt -no FSTYPE /mnt/sonde-fs)" = ceph ]'
  check_ssh "$_m08x_client : /mnt/sonde-fs répond en moins de 10 s (lecture du témoin)" "$_m08x_client" \
    'sudo -n bash -c '\''( cat /mnt/sonde-fs/temoin >/dev/null ) & p=$!; i=0; while kill -0 $p 2>/dev/null && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done; ! kill -0 $p 2>/dev/null && wait $p'\'''
else
  skip "montage CephFS témoin" "témoins pas encore créés (créés à la première injection)"
fi
check_cmd "panne M08-E41 close (lab/bin/break 08 41 --annuler après réparation)" _m08x_aucune_panne_active E41
