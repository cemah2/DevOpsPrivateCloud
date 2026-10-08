# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : pas d'expansion voulue
#
# check-E14.sh — M09-E14 : Réplication ZFS entre nœuds
# À lancer depuis adm01. Lecture seule (configuration et état de la réplication, zfs list).

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E14 — Réplication ZFS entre nœuds"
require_cmd jq

_m09o_res="$(_m09o_ressources)"
check_cmd "rep01 (110) existe" _m09o_vm_existe "$_m09o_res" 110
check_cmd "rep01 (110) : disque(s) sur zfs-local" _m09o_disques_sur "$(_m09o_conf 110)" zfs-local
_m09o_src="$(jq -r 'map(select(.vmid == 110))[0].node // empty' <<<"$_m09o_res" 2>/dev/null || true)"

_m09o_j="$(_m09o_pvesh /cluster/replication)"
check_cmd "deux tâches de réplication pour 110, vers deux nœuds différents" _m09o_json "$_m09o_j" \
  '[.[] | select(.guest == 110 or .guest == "110")] | length == 2 and (map(.target) | unique | length == 2)'
check_cmd "tâches de 110 : horaire */10, débit limité à 20 Mo/s" _m09o_json "$_m09o_j" \
  '[.[] | select(.guest == 110 or .guest == "110")] | length == 2
   and all(.[]; .schedule == "*/10" and ((.rate // 0) | tonumber) == 20)'
check_cmd "tâches de 110 : aucune cible n'est le nœud où tourne la VM (${_m09o_src:-?})" _m09o_json "$_m09o_j" \
  '[.[] | select(.guest == 110 or .guest == "110") | .target] | length == 2 and (index($n) == null)' --arg n "${_m09o_src:-?}"

if [[ -n "$_m09o_src" ]]; then
  _m09o_st="$(_m09o_hv "$_m09o_src" "pvesh get /nodes/$_m09o_src/replication --guest 110 --output-format json")"
  check_cmd "dernière synchronisation de chaque tâche il y a moins de 30 min, sans échec en cours" _m09o_json "$_m09o_st" \
    'length == 2 and all(.[]; ((.fail_count // 0) == 0) and ((.last_sync // 0) > (now - 1800)))'
  for _m09o_t in $(jq -r '.[] | select(.guest == 110 or .guest == "110") | .target' <<<"$_m09o_j" 2>/dev/null || true); do
    check_ssh "$_m09o_t : copie du disque de rep01 avec un instantané de réplication" "$_m09o_t" \
      'zfs list -H -t snapshot -o name -r tank 2>/dev/null | grep -q "vm-110-disk-[0-9]*@__replicate_110-"'
  done
else
  skip "état de la réplication" "rep01 (110) introuvable"
fi
