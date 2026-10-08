# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
#
# check-E32.sh — M07-E32 « Tester et mesurer les bascules »
# Lecture seule : compte rendu dans la copie de travail de la documentation, état final de la bordure
# (adresses, keepalived, règles, configuration Proxmox des cartes).

# shellcheck source=_m07-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-production.sh"

title "M07-E32 — Tester et mesurer les bascules"
require_cmd ssh
_m07p_charger_adresses gw01 gw02
_m07_cr="$_M07P_DEPOT/docs/socle/tests/bascules.md"

title "Compte rendu"
check_cmd "bascules.md : au moins sept scénarios avec des valeurs mesurées" bash -c \
  '[ "$(grep -Ec "^\| *[0-9]+ *\|.*[0-9]+([,.][0-9]+)? ?(s|ms) *\|" "$1")" -ge 7 ]' _ "$_m07_cr"
check_cmd "bascules.md : perte des annonces sur un VLAN (cerveau divisé) observée et expliquée" bash -c 'grep -qiE "cerveau divisé|split.?brain" "$1"' _ "$_m07_cr"
check_cmd "bascules.md : scénarios non testés listés" bash -c 'grep -qiE "non test" "$1"' _ "$_m07_cr"

title "Retour à l'état nominal"
for _m07_v in "${_M07P_VLANS[@]}"; do
  check_cmd "VLAN $_m07_v : une seule passerelle porte la VIP" _m07p_vip_unique "10.10.$_m07_v.1" gw01 gw02
done
check_cmd "toutes les VIP de la bordure sur la même passerelle" _m07p_vips_bordure_ensemble
for _m07_h in gw01 gw02; do
  check_ssh "$_m07_h : keepalived actif, état MASTER ou BACKUP (pas FAULT)" "$_m07_h" \
    'systemctl is-active -q keepalived && grep -Eqx "MASTER|BACKUP" /run/bordure/etat'
  check_ssh "$_m07_h : aucune règle de test restante (TEST-E32)" "$_m07_h" '! sudo -n nft list ruleset | grep -q "TEST-E32"'
done
for _m07_id in 1000 1009; do
  check_ssh "VM $_m07_id : aucune carte déconnectée (link_down)" "$WB_PVE_HOST" "! qm config $_m07_id | grep -E '^net[0-9]+:' | grep -q 'link_down=1'"
  check_ssh "VM $_m07_id : démarrée" "$WB_PVE_HOST" "qm status $_m07_id | grep -q running"
done
