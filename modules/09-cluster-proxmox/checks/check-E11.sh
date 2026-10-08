# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : pas d'expansion voulue
#
# check-E11.sh — M09-E11 : Stockage partagé et migration à chaud
# À lancer depuis adm01. Lecture seule (configurations dans pmxcfs, ressources et tâches du cluster).

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E11 — Stockage partagé et migration à chaud"
require_cmd jq

_m09o_res="$(_m09o_ressources)"
check_cmd "le cluster répond (pvesh get /cluster/resources)" _m09o_json "$_m09o_res" 'type == "array"'

_m09o_c="$(_m09o_conf 199)"
check_output "template 199 : c'est un template" '^template: 1' echo "$_m09o_c"
check_cmd "template 199 : son disque est sur ceph-vm" _m09o_disques_sur "$_m09o_c" ceph-vm

for _m09o_id in 101 102 103; do
  _m09o_c="$(_m09o_conf "$_m09o_id")"
  check_cmd "invité $_m09o_id existe" _m09o_vm_existe "$_m09o_res" "$_m09o_id"
  check_cmd "invité $_m09o_id : tous ses disques sont sur ceph-vm (aucun disque local)" _m09o_disques_sur "$_m09o_c" ceph-vm
  check_cmd "invité $_m09o_id : aucun volume orphelin « unusedN » laissé par un déplacement" \
    bash -c '[[ -n "$1" ]] && ! grep -q "^unused[0-9]*:" <<<"$1"' _ "$_m09o_c"
done

for _m09o_id in 104 105 106; do
  # « absent » ne prouve rien si la liste n'a pas pu être lue : on exige une liste non vide.
  check_cmd "invité d'essai $_m09o_id détruit" _m09o_json "$_m09o_res"     'length > 0 and (map(select(.vmid == $id)) | length == 0)' --argjson id "$_m09o_id"
done

_m09o_t="$(_m09o_pvesh /cluster/tasks)"
check_cmd "historique des tâches : une migration (qmigrate) de app01 (101) terminée avec succès" _m09o_json "$_m09o_t" \
  'map(select(.type == "qmigrate" and .id == "101" and .status == "OK")) | length > 0'
