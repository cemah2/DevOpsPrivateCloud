# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E10.sh — M09-E10 : Ceph hyperconvergé
# À lancer depuis adm01. Lecture seule (ceph … en lecture, pvesm status, ping sans fragmentation).

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E10 — Ceph hyperconvergé"
require_cmd jq

check_cmd "les trois nœuds répondent en SSH (alias hv01, hv02, hv03)" _m09o_tous_joignables

_m09o_st="$(_m09o_ceph status)"
check_cmd "Ceph répond (ceph status) sur un nœud du cluster" _m09o_json "$_m09o_st" '.fsid != null'
check_cmd "santé : HEALTH_OK" _m09o_json "$_m09o_st" '.health.status == "HEALTH_OK"'
check_cmd "3 moniteurs, tous dans le quorum" _m09o_json "$_m09o_st" '.monmap.num_mons == 3 and (.quorum_names | length) == 3'
check_cmd "1 gestionnaire actif et 2 en attente" _m09o_json "$_m09o_st" '.mgrmap.available == true and .mgrmap.num_standbys == 2'
check_cmd "6 OSD, tous up et in" _m09o_json "$_m09o_st" '.osdmap.num_osds == 6 and .osdmap.num_up_osds == 6 and .osdmap.num_in_osds == 6'

# --- Réseaux -----------------------------------------------------------------------------------------
_m09o_cc="$(_m09o_hv "$(_m09o_noeud)" 'cat /etc/pve/ceph.conf')"
check_output "ceph.conf (pmxcfs) : réseau public 10.10.30.0/24" 'public_network *= *10\.10\.30\.0/24' echo "$_m09o_cc"
check_output "ceph.conf (pmxcfs) : réseau cluster 10.10.31.0/24" 'cluster_network *= *10\.10\.31\.0/24' echo "$_m09o_cc"
_m09o_osd="$(_m09o_ceph 'osd dump')"
check_cmd "chaque OSD écoute sur 10.10.30.x (public) et 10.10.31.x (cluster)" _m09o_json "$_m09o_osd" \
  '(.osds | length) == 6 and all(.osds[];
     ([.public_addrs.addrvec[]?.addr] | all(startswith("10.10.30.")))
     and ([.cluster_addrs.addrvec[]?.addr] | all(startswith("10.10.31."))))'
for _m09o_n in $_M09O_NOEUDS; do
  check_ssh "$_m09o_n : MTU 9000 de bout en bout sur 10.10.30.0/24 et 10.10.31.0/24 (ping 8972 octets, sans fragmentation)" "$_m09o_n" \
    'for r in 30 31; do for i in 71 72 73; do ip -4 -o addr show | grep -q " 10.10.$r.$i/" && continue;
       ping -c 1 -W 2 -M do -s 8972 10.10.$r.$i >/dev/null || exit 1; done; done'
done

# --- Mémoire, pool, stockage, version ------------------------------------------------------------------
check_output "osd_memory_target = 1073741824 (1 Gio) dans la base de configuration" '^"?1073741824"?$' \
  _m09o_hv "$(_m09o_noeud)" 'ceph config get osd osd_memory_target'
_m09o_pools="$(_m09o_ceph 'osd pool ls detail')"
check_cmd "pool ceph-vm : size 3, min_size 2" _m09o_json "$_m09o_pools" \
  'map(select(.pool_name == "ceph-vm")) | length == 1 and (.[0].size == 3 and .[0].min_size == 2)'
check_cmd "pool ceph-vm : application rbd, ajustement automatique des PG « on »" _m09o_json "$_m09o_pools" \
  'map(select(.pool_name == "ceph-vm"))[0] | (.application_metadata | has("rbd")) and .pg_autoscale_mode == "on"'
_m09o_s="$(_m09o_stockage_cfg ceph-vm)"
check_output "stockage ceph-vm : type rbd, pool ceph-vm" '^rbd: ceph-vm' echo "$_m09o_s"
check_cmd "stockage ceph-vm : Ceph du cluster (pas de monhost : ce n'est pas un stockage externe)" \
  bash -c '[[ -n "$1" ]] && ! grep -q "monhost" <<<"$1"' _ "$_m09o_s"
check_cmd "stockage ceph-vm actif sur les trois nœuds" _m09o_stockage_actif_partout ceph-vm
_m09o_v="$(_m09o_ceph versions)"
check_cmd "démons Ceph en Squid 19.2 (ou Tentacle 20.2 après M09-E28), une seule version" _m09o_json "$_m09o_v" \
  '(.overall | keys | length) == 1 and (.overall | keys[0] | test("ceph version (19\\.2|20\\.2)\\."))'
