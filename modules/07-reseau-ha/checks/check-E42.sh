# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E42.sh — M07-E42 « Panne : la fabric perd la moitié de son trafic » : ECMP sur les deux spines,
# spines qui relaient, apprentissage complet, joignabilité entre boucles. Lecture seule.

# shellcheck source=_m07-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-expert.sh"

title "M07-E42 — ECMP de la fabric leaf-spine"
require_cmd ssh jq

_m07_e42_ecmp() { local s; s="$(_m07x_sauts "$1" "$2")"; [[ -n "$s" && "$s" -ge 2 ]]; }
check_cmd "leaf01 : deux chemins (ECMP) vers la boucle de leaf02 (10.10.255.12)" _m07_e42_ecmp leaf01 10.10.255.12/32
check_cmd "leaf02 : deux chemins (ECMP) vers la boucle de leaf01 (10.10.255.11)" _m07_e42_ecmp leaf02 10.10.255.11/32
for _m07_e42_h in leaf01 leaf02; do
  check_cmd "$_m07_e42_h : ECMP non bridé (pas de « maximum-paths 1 »)" _m07x_ok "$_m07_e42_h" \
    "! vtysh -c 'show running-config' | grep -Eq '^[[:space:]]*maximum-paths[[:space:]]+1[[:space:]]*\$'"
done
_m07_e42_pas_force() { ! _m07x_sysctl_force "$1" net.ipv4.ip_forward 0; }
for _m07_e42_h in spine01 spine02; do
  check_cmd "$_m07_e42_h : relais IPv4 actif" _m07x_ok "$_m07_e42_h" '[ "$(sysctl -n net.ipv4.ip_forward)" = 1 ]'
  check_cmd "$_m07_e42_h : aucun fichier sysctl ne désactive le relais au prochain démarrage" _m07_e42_pas_force "$_m07_e42_h"
  check_cmd "$_m07_e42_h : sessions établies avec les deux leaves, routes reçues de chacun" bash -c '
    [ "$(awk '\''$2 == "Established" && $4 > 0 && ($3 == "65101" || $3 == "65102") { print $3 }'\'' <<<"$1" | sort -u | wc -l)" -ge 2 ]' \
    _ "$(_m07x_pairs "$_m07_e42_h")"
done
_m07_e42_tous() {
  _m07x_ok srv01 'for d in 10.10.255.22 10.10.255.12; do ping -n -c 2 -W 2 -I 10.10.255.21 $d || exit 1; done' &&
    _m07x_ok leaf01 'for d in 10.10.255.22 10.10.255.12; do ping -n -c 2 -W 2 -I 10.10.255.11 $d || exit 1; done' &&
    _m07x_ok srv02 'ping -n -c 2 -W 2 -I 10.10.255.22 10.10.255.11'
}
check_cmd "joignabilité entre boucles : srv01 → srv02/leaf02, leaf01 → srv02/leaf02, srv02 → leaf01" _m07_e42_tous
check_cmd "panne M07-E42 close (lab/bin/break 07 42 --annuler après réparation)" _m07x_aucune_panne_active E42
