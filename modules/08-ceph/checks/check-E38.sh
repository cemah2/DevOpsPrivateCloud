# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E38.sh — M08-E38 « Panne : les moniteurs perdent le quorum » : quorum complet, horloges
# synchronisées, ports des MON joignables, aucun filtrage posé à chaud. Lecture seule.

# shellcheck source=_m08-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-expert.sh"

title "M08-E38 — Les moniteurs sont en quorum"
require_cmd jq ssh

check_cmd "les moniteurs répondent au nœud $_m08x_admin" _m08x_cluster_repond
if _m08x_cluster_repond; then
  check_cmd "trois moniteurs dans la carte, tous dans le quorum" \
    _m08x_jq '.status.monmap.num_mons >= 3 and (.status.quorum_names | length) == .status.monmap.num_mons'
  check_cmd "aucun décalage d'horloge signalé (MON_CLOCK_SKEW)" _m08x_jq '.health.checks | has("MON_CLOCK_SKEW") | not'
  check_cmd "aucun moniteur signalé absent (MON_DOWN)" _m08x_jq '.health.checks | has("MON_DOWN") | not'
fi
for _m08_e38_h in "${_m08x_noeuds[@]}"; do
  check_port "$_m08_e38_h : port msgr2 des MON (3300) joignable depuis adm01" "${_m08x_ip_pub[$_m08_e38_h]}" 3300
  check_port "$_m08_e38_h : port msgr1 des MON (6789) joignable depuis adm01" "${_m08x_ip_pub[$_m08_e38_h]}" 6789
  check_ssh "$_m08_e38_h : chronyd actif et synchronisé (décalage < 0,1 s)" "$_m08_e38_h" \
    'systemctl is-active -q chronyd && chronyc -n tracking | awk '\''/^System time/ { t = $4 } /^Leap status/ { l = $4 } END { exit !(t != "" && t < 0.1 && l == "Normal") }'\'''
  check_ssh "$_m08_e38_h : aucune table nftables posée hors firewalld qui filtre les ports Ceph" "$_m08_e38_h" \
    '! sudo -n nft list ruleset 2>/dev/null | grep -E "(3300|6789)" | grep -qw drop'
  check_ssh "$_m08_e38_h : aucune unité ceph masquée ou en échec" "$_m08_e38_h" "sudo -n bash -c $(printf '%q' "$_m08x_cmd_unites_saines")"
done
check_cmd "panne M08-E38 close (lab/bin/break 08 38 --annuler après réparation)" _m08x_aucune_panne_active E38
