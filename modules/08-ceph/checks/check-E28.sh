# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E28.sh — M08-E28 « Mesurer les performances »
# Lecture seule : pools, configuration des moniteurs, MTU des interfaces de cluster (ip link), ping
# sans fragmentation entre nœuds, documentation et profils fio (API GitLab).

# shellcheck source=_m08-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-production.sh"

title "M08-E28 — Mesurer les performances"
require_cmd jq curl
_m08p_charger
check_cmd "le cluster répond depuis $_M08P_ADMIN (ceph status)" _m08p_joignable

title "Nettoyage"
check_cmd "le pool de mesure « bench » n'existe plus" _m08p_pool_absent bench
check_output "la suppression de pool est de nouveau interdite (mon_allow_pool_delete)" '^false$' \
  _m08p_config_get mon mon_allow_pool_delete
for _m08_e28_h in $(_m08p_hotes_orch 2>/dev/null || printf '%s ' "${_M08P_NOEUDS[@]}"); do
  check_cmd "$_m08_e28_h : interface du réseau de cluster (ens19) en MTU 9000" _m08p_mtu "$_m08_e28_h" ens19 9000
done
_m08_e28_ping() { _m08p_ping_jumbo ceph01 10.10.31.52 && _m08p_ping_jumbo ceph01 10.10.31.53; }
check_cmd "ceph01 → ceph02 et ceph03 : 9000 octets sans fragmentation sur le VLAN 31" _m08_e28_ping

title "Documentation et méthode"
check_cmd "docs/stockage/performances.md sur main : méthode et outils (iperf3, rados bench, rbd bench, fio)" \
  _m08p_doc_main docs/stockage/performances.md 'iperf3' 'rados bench' 'rbd bench' 'fio'
check_cmd "performances.md : centiles de latence et comparaison MTU 1500 / 9000" \
  _m08p_doc_main docs/stockage/performances.md '(p99|99(\.0+)? ?(e|è)?(me)? ?centile|percentile|clat)' '1500' '9000'
check_cmd "plateforme/ceph : profils fio versionnés sous bench/" _m08p_arbre_non_vide plateforme/ceph bench
