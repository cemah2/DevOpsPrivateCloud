# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes et filtres entre apostrophes (hôte distant, jq)
# check-E42.sh — M08-E42 « Panne : le cluster est lent » : jumbo frames de bout en bout sur le réseau
# cluster, aucune limitation de débit ni filtrage par taille, délestages actifs, ordonnanceur mClock
# sans limite client artificielle, aucun battement de cœur lent signalé. Lecture seule.

# shellcheck source=_m08-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-expert.sh"

title "M08-E42 — Le cluster a retrouvé ses performances"
require_cmd jq ssh

for _m08_e42_h in "${_m08x_noeuds[@]}"; do
  check_ssh "$_m08_e42_h : ens19 en MTU 9000" "$_m08_e42_h" '[ "$(cat /sys/class/net/ens19/mtu)" = 9000 ]'
  check_ssh "$_m08_e42_h : aucune file tbf/netem sur ens19" "$_m08_e42_h" '! tc qdisc show dev ens19 2>/dev/null | grep -Eq "qdisc (tbf|netem)"'
  check_ssh "$_m08_e42_h : aucun filtrage par taille ni limitation de débit nftables" "$_m08_e42_h" \
    '! sudo -n nft list ruleset 2>/dev/null | grep -Eq "meta length|limit rate over"'
  check_ssh "$_m08_e42_h : délestages GRO/GSO/TSO actifs sur ens19" "$_m08_e42_h" \
    '! ethtool -k ens19 2>/dev/null | grep -Eq "^(generic-receive-offload|generic-segmentation-offload|tcp-segmentation-offload): off$"'
  for _m08_e42_d in "${_m08x_noeuds[@]}"; do
    [[ "$_m08_e42_d" == "$_m08_e42_h" ]] && continue
    check_ssh "$_m08_e42_h → $_m08_e42_d : 8972 octets sans fragmentation sur le réseau cluster" "$_m08_e42_h" \
      "ping -c 2 -W 2 -M do -s 8972 ${_m08x_ip_clu[$_m08_e42_d]} >/dev/null"
  done
done
if _m08x_cluster_repond; then
  check_cmd "mClock : pas de limite client artificielle (osd_mclock_scheduler_client_lim)" \
    _m08x_jq '[.config[] | select(.name == "osd_mclock_scheduler_client_lim") | .value | tonumber] | all(. == 0 or . >= 0.5)'
  check_cmd "mClock : profil client ou équilibré (pas « custom » sans justification)" \
    _m08x_jq '[.config[] | select(.name == "osd_mclock_profile") | .value] | all(. != "custom")'
  check_cmd "aucun battement de cœur lent ni requête lente (OSD_SLOW_PING_TIME_*, SLOW_OPS)" \
    _m08x_jq '.health.checks | (has("OSD_SLOW_PING_TIME_BACK") or has("OSD_SLOW_PING_TIME_FRONT") or has("SLOW_OPS")) | not'
  check_cmd "tous les OSD up (aucun oscillant marqué down)" _m08x_jq '.status.osdmap.num_osds == .status.osdmap.num_up_osds'
else
  skip "réglages et santé" "les moniteurs ne répondent pas au nœud $_m08x_admin"
fi
check_cmd "panne M08-E42 close (lab/bin/break 08 42 --annuler après réparation)" _m08x_aucune_panne_active E42
