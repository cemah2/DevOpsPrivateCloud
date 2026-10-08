# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E35.sh — M07-E35 « Panne : la session BGP ne monte pas » : session eBGP leaf01 ↔ bordure
# établie, annonces conformes aux politiques, RFC 8212 toujours appliquée. Lecture seule.

# shellcheck source=_m07-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-expert.sh"

title "M07-E35 — Session BGP entre la fabric et la bordure"
require_cmd ssh jq

check_cmd "leaf01 : FRR actif" _m07x_ok leaf01 'systemctl is-active -q frr'
_m07_e35_p="$(_m07x_pairs leaf01 65000)"
check_cmd "leaf01 : au moins une session vers l'AS 65000 établie" \
  bash -c 'grep -q " Established " <<<"$1"' _ "$_m07_e35_p"
check_cmd "leaf01 : des préfixes sont annoncés à la bordure (aucun pair « (Policy) »)" \
  bash -c 'awk '\''$2 == "Established" && $5 > 0 { ok = 1 } END { exit !ok }'\'' <<<"$1"' _ "$_m07_e35_p"
check_cmd "leaf01 : aucune session vers l'AS 65000 configurée mais tombée" \
  bash -c '[ -n "$1" ] && ! awk '\''$2 != "Established"'\'' <<<"$1" | grep -q .' _ "$_m07_e35_p"
check_cmd "leaf01 : bgp ebgp-requires-policy toujours actif (RFC 8212)" _m07x_ok leaf01 '
  c="$(vtysh -c "show running-config")"
  ! echo "$c" | grep -q "no bgp ebgp-requires-policy" || exit 1
  ! echo "$c" | grep -q "frr defaults datacenter" || echo "$c" | grep -q "^ *bgp ebgp-requires-policy"'
check_cmd "leaf01 : aucun filtrage du port TCP 179" _m07x_ok leaf01 \
  "! nft list ruleset 2>/dev/null | grep -E '(dport|sport) 179' | grep -Eq '(drop|reject)'"
for _m07_e35_gw in gw01 gw02; do
  if [[ "$_m07_e35_gw" == gw02 ]] && ! _m07x_existe gw02; then
    skip "gw02 : routes de la fabric" "gw02 absente (M07-E24)"
    continue
  fi
  check_cmd "$_m07_e35_gw : routes BGP vers les boucles de la fabric (10.10.255.0/24)" \
    _m07x_ok "$_m07_e35_gw" "ip -4 route show proto bgp | grep -q '^10\.10\.255\.'"
  check_cmd "$_m07_e35_gw : aucune route BGP hors politique (seulement 10.10.255/24, 10.10.41/24, 10.30/16)" \
    _m07x_ok "$_m07_e35_gw" "! ip -4 route show proto bgp | grep -vE '^(10\.10\.255\.|10\.10\.41\.|10\.30\.)' | grep -q ."
done
check_cmd "panne M07-E35 close (lab/bin/break 07 35 --annuler après réparation)" _m07x_aucune_panne_active E35
