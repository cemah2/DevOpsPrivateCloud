# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E14.sh — M08-E14 : CRUSH : règles par classe et domaines de panne
# À lancer depuis adm01. Lecture seule (osd tree, crush rule dump, pool ls detail, status).

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E14 — CRUSH : règles par classe et domaines de panne"
require_cmd jq

_m08o_arbre="$(_m08o_ceph osd tree --format json)"
_m08o_regles="$(_m08o_ceph osd crush rule dump --format json)"
_m08o_pools="$(_m08o_ceph osd pool ls detail --format json)"
_m08o_statut="$(_m08o_ceph status --format json)"

# --- Hiérarchie ----------------------------------------------------------------------------------
check_output "datacenter par1 rattaché à la racine default" '^default$' _m08o_parent "$_m08o_arbre" par1
for _m08o_b in a b c; do
  check_output "baie par1-baie-$_m08o_b rattachée à par1" '^par1$' _m08o_parent "$_m08o_arbre" "par1-baie-$_m08o_b"
done
check_output "ceph01 dans par1-baie-a" '^par1-baie-a$' _m08o_parent "$_m08o_arbre" ceph01
check_output "ceph02 dans par1-baie-b" '^par1-baie-b$' _m08o_parent "$_m08o_arbre" ceph02
check_output "ceph03 dans par1-baie-c" '^par1-baie-c$' _m08o_parent "$_m08o_arbre" ceph03

# --- Règles ----------------------------------------------------------------------------------------
for _m08o_c in ssd hdd; do
  check_cmd "règle $_m08o_c-baie : classe $_m08o_c, domaine de panne rack" \
    jq -e --arg r "$_m08o_c-baie" --arg t "default~$_m08o_c" '.[] | select(.rule_name == $r)
      | ([.steps[] | select(.op == "take")][0].item_name == $t)
        and ([.steps[] | select(.op | test("chooseleaf"))][0].type == "rack")' <<<"$_m08o_regles"
done
_m08o_id_ssd="$(jq -r '.[] | select(.rule_name == "ssd-baie") | .rule_id' <<<"$_m08o_regles" 2>/dev/null || true)"

# --- Pools -----------------------------------------------------------------------------------------
_m08o_hors_regle="$(jq -r --argjson r "$_m08o_regles" '
  ($r | map(select(.rule_name == "ssd-baie" or .rule_name == "hdd-baie") | .rule_id)) as $ok
  | [.[] | select(.type == 1 and ((.crush_rule as $c | $ok | index($c)) | not)) | .pool_name] | join(" ")' <<<"$_m08o_pools" 2>/dev/null || echo "?")"
check_output "tous les pools répliqués sur ssd-baie ou hdd-baie (hors règle : ${_m08o_hors_regle:-aucun})" '^$' echo "$_m08o_hors_regle"
_m08o_defaut="$(_m08o_ceph config get global osd_pool_default_crush_rule | tr -d '[:space:]')"
check_output "osd_pool_default_crush_rule désigne ssd-baie (id ${_m08o_id_ssd:-?} ; valeur : ${_m08o_defaut:-?})" \
  "^${_m08o_id_ssd:-x}$" echo "$_m08o_defaut"
check_cmd "tous les PG sont active+clean" _m08o_pgs_propres "$_m08o_statut"

# --- Travail hors ligne ----------------------------------------------------------------------------
check_cmd "dossier m08/e14 : une carte CRUSH décompilée" \
  bash -c 'grep -lqs "^rule " "$1"/*.txt' _ "$_M08O_TRAVAIL/e14"
