# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E14.sh — M07-E14 : Fabric leaf-spine : BGP unnumbered et ECMP
# À lancer depuis adm01, spines, leaves et serveurs de la maquette démarrés. Lecture seule.

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E14 — Fabric leaf-spine : BGP unnumbered et ECMP"
require_cmd jq

declare -A _m07o_as=([spine01]=65100 [spine02]=65100 [leaf01]=65101 [leaf02]=65102)
declare -A _m07o_boucle=([spine01]=10.10.255.1 [spine02]=10.10.255.2 [leaf01]=10.10.255.11 [leaf02]=10.10.255.12)

for _m07o_h in spine01 spine02 leaf01 leaf02; do
  _m07o_resume="$(_m07o_vtysh "$_m07o_h" 'show bgp ipv4 unicast summary json')"
  check_output "$_m07o_h : AS ${_m07o_as[$_m07o_h]}" "^${_m07o_as[$_m07o_h]}\$" \
    jq -r '.as // empty' <<<"$_m07o_resume"
  # Voisins « unnumbered » : la clé du voisin est le NOM de l'interface (eth1, eth2), pas une
  # adresse ; et aucun voisin de la fabric n'est plus désigné par une adresse /31.
  check_output "$_m07o_h : sessions établies sur eth1 et eth2 (voisins désignés par l'interface)" '^2$' \
    jq -r '[.peers // {} | to_entries[] | select((.key == "eth1" or .key == "eth2") and .value.state == "Established")] | length' <<<"$_m07o_resume"
  check_output "$_m07o_h : plus aucun voisin désigné par une adresse de lien /31" '^0$' \
    jq -r '[.peers // {} | keys[] | select(startswith("10.10.250."))] | length' <<<"$_m07o_resume"
  check_ssh "$_m07o_h : boucle ${_m07o_boucle[$_m07o_h]}/32 sur lo" "$_m07o_h" \
    "ip -4 -o addr show dev lo | grep -q ' ${_m07o_boucle[$_m07o_h]}/32 '"
  # Actif = pas désactivé ; et, sous le profil datacenter (où il est désactivé par défaut), écrit.
  check_output "$_m07o_h : bgp ebgp-requires-policy actif" '^actif$' bash -c '
    c="$1"
    grep -q "^router bgp" <<<"$c" || { echo absent; exit 0; }
    grep -q "no bgp ebgp-requires-policy" <<<"$c" && { echo desactive; exit 0; }
    if grep -q "^frr defaults datacenter" <<<"$c" && ! grep -q "^ bgp ebgp-requires-policy" <<<"$c"; then
      echo "desactive (profil datacenter)"; exit 0
    fi
    echo actif' _ "$(_m07o_vtysh "$_m07o_h" 'show running-config')"
done

# ECMP : deux next-hops dans le NOYAU, d'une leaf vers la boucle de l'autre.
for _m07o_p in leaf01:10.10.255.12 leaf02:10.10.255.11; do
  _m07o_h="${_m07o_p%%:*}"
  check_output "$_m07o_h : deux chemins égaux vers ${_m07o_p#*:} dans le noyau" '^2$' bash -c \
    'jq -r "[.[0].nexthops // [] | .[]] | length" <<<"$1" 2>/dev/null || echo 0' \
    _ "$(remote "$_m07o_h" "ip -j route show ${_m07o_p#*:}/32" 2>/dev/null || true)"
  check_ssh "$_m07o_h : répartition ECMP selon les ports (fib_multipath_hash_policy = 1)" "$_m07o_h" \
    '[ "$(sysctl -n net.ipv4.fib_multipath_hash_policy)" = 1 ]'
done

check_ssh "srv01 joint srv02 de boucle à boucle (10.10.255.21 → 10.10.255.22)" srv01 \
  'ping -c 3 -W 2 -I 10.10.255.21 10.10.255.22 >/dev/null'
check_ssh "srv02 joint la boucle de spine01 (route vers la fabric)" srv02 \
  'ping -c 2 -W 2 -I 10.10.255.22 10.10.255.1 >/dev/null'
