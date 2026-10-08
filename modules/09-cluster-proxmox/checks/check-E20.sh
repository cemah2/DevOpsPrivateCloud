# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : pas d'expansion voulue
#
# check-E20.sh — M09-E20 : Évacuer un nœud, équilibrer la charge
# À lancer depuis adm01. Lecture seule (datacenter.cfg, état HA, ressources du cluster).

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E20 — Évacuer un nœud, équilibrer la charge"
require_cmd jq

_m09o_dc="$(_m09o_hv "$(_m09o_noeud)" 'cat /etc/pve/datacenter.cfg')"
check_output "datacenter.cfg : politique d'arrêt HA « migrate »" '^ha:.*shutdown_policy=migrate' echo "$_m09o_dc"
_m09o_crs="$(sed -n 's/^crs:[[:space:]]*//p' <<<"$_m09o_dc")"
check_output "planificateur (CRS) : ha=dynamic" '(^|,)ha=dynamic(,|$)' echo "$_m09o_crs"
check_output "planificateur : ha-rebalance-on-start=1" '(^|,)ha-rebalance-on-start=1(,|$)' echo "$_m09o_crs"
check_output "équilibrage automatique actif (ha-auto-rebalance=1)" '(^|,)ha-auto-rebalance=1(,|$)' echo "$_m09o_crs"
check_output "seuil de déséquilibre : 40 %" '(^|,)ha-auto-rebalance-threshold=40(,|$)' echo "$_m09o_crs"

_m09o_e="$(_m09o_ha_etat)"
check_cmd "HA armée (état du fencing : armed)" _m09o_json "$_m09o_e" \
  'map(select(.type == "fencing"))[0] | . != null and ((."armed-state" // .status // "") | test("^armed"))'
check_cmd "aucun nœud en maintenance" bash -c '[[ -n "$1" ]] && ! grep -qi "maintenance" <<<"$1"' _ \
  "$(_m09o_hv "$(_m09o_noeud)" 'ha-manager status')"
check_cmd "toutes les ressources HA sont started" _m09o_json "$_m09o_e" \
  '(map(select(.type == "service")) | length > 0) and all(.[] | select(.type == "service"); .state == "started")'

_m09o_res="$(_m09o_ressources)"
check_cmd "les VMs HA démarrées ne sont pas toutes sur le même nœud" bash -c \
  'jq -e --argjson sids "$(jq -c "[.[] | select(.type == \"service\") | .sid]" <<<"$2")" \
     "[.[] | select(.status == \"running\") | select((\"vm:\" + (.vmid | tostring)) as \$s | \$sids | index(\$s) != null) | .node] | unique | length >= 2" \
     <<<"$1" >/dev/null' _ "$_m09o_res" "$_m09o_e"
check_cmd "règle frontaux-separes respectée : app02 (102) et app03 (103) sur deux nœuds" _m09o_json "$_m09o_res" \
  '(map(select(.vmid == 102))[0].node) != (map(select(.vmid == 103))[0].node)'
check_cmd "aucune règle HA désactivée" _m09o_json "$(_m09o_pvesh /cluster/ha/rules)" \
  'map(select(((.disable // 0) | tostring) | test("^(1|true)$"))) | length == 0'
