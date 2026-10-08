# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : pas d'expansion voulue
#
# check-E13.sh — M09-E13 : Haute disponibilité : ressources et règles
# À lancer depuis adm01. Lecture seule (API HA et ressources du cluster).

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E13 — Haute disponibilité : ressources et règles"
require_cmd jq

_m09o_r="$(_m09o_ha_ressources)"
_m09o_e="$(_m09o_ha_etat)"
_m09o_g="$(_m09o_pvesh /cluster/ha/rules)"
_m09o_res="$(_m09o_ressources)"

for _m09o_id in 101 102 103; do
  # max_restart / max_relocate : 1 explicite, ou absents (= valeur par défaut 1, ha-manager(1)).
  check_cmd "vm:$_m09o_id : ressource HA, état demandé started, max_restart 1, max_relocate 1" _m09o_json "$_m09o_r" \
    'map(select(.sid == $s))[0] | . != null and .state == "started"
       and ((.max_restart // 1) == 1) and ((.max_relocate // 1) == 1)' --arg s "vm:$_m09o_id"
  check_cmd "vm:$_m09o_id : started selon le gestionnaire HA" _m09o_json "$_m09o_e" \
    'map(select(.type == "service" and .sid == $s and .state == "started")) | length == 1' --arg s "vm:$_m09o_id"
done

check_cmd "le gestionnaire HA a un maître et le quorum" _m09o_json "$_m09o_e" \
  '(map(select(.type == "master")) | length == 1) and (map(select(.type == "quorum" and (((.quorate // 0) | tostring | test("^(1|true)$")) or ((.status // "") | test("OK"))))) | length == 1)'
check_cmd "aucune ressource HA en état error" _m09o_json "$_m09o_e" 'map(select(.type == "service" and .state == "error")) | length == 0'

check_cmd "règle app01-preferences : affinité de nœud sur vm:101, non stricte, active" _m09o_json "$_m09o_g" \
  'map(select(.rule == "app01-preferences"))[0]
   | . != null and .type == "node-affinity" and (.resources | test("(^|,)vm:101(,|$)"))
     and ((.strict // 0) | tostring | test("^(0|false)$")) and ((.disable // 0) | tostring | test("^(0|false)$"))'
check_cmd "règle app01-preferences : priorités hv01 > hv02 > hv03" _m09o_json "$_m09o_g" \
  'map(select(.rule == "app01-preferences"))[0].nodes | split(",")
   | map(split(":") | {(.[0]): ((.[1] // "0") | tonumber)}) | add
   | (.hv01 // -1) > (.hv02 // -1) and (.hv02 // -1) > (.hv03 // -1)'
check_cmd "règle frontaux-separes : affinité de ressources négative sur vm:102 et vm:103, active" _m09o_json "$_m09o_g" \
  'map(select(.rule == "frontaux-separes"))[0]
   | . != null and .type == "resource-affinity" and .affinity == "negative"
     and (.resources | test("(^|,)vm:102(,|$)")) and (.resources | test("(^|,)vm:103(,|$)"))
     and ((.disable // 0) | tostring | test("^(0|false)$"))'

check_cmd "app01 (101) tourne sur hv01" _m09o_json "$_m09o_res" \
  'map(select(.vmid == 101))[0] | .node == "hv01" and .status == "running"'
check_cmd "app02 (102) et app03 (103) tournent sur deux nœuds différents" _m09o_json "$_m09o_res" \
  '(map(select(.vmid == 102))[0]) as $a | (map(select(.vmid == 103))[0]) as $b
   | $a.status == "running" and $b.status == "running" and $a.node != $b.node'
