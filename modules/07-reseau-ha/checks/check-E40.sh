# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E40.sh — M07-E40 « Panne : l'agrégat a perdu un lien » : bond Linux 802.3ad de net01 avec deux
# ports dans l'agrégateur actif, partenaire LACP connu, LACP négocié côté Open vSwitch. Lecture seule.

# shellcheck source=_m07-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-expert.sh"

title "M07-E40 — Agrégat LACP de net01"
require_cmd ssh jq

# Script distant : trouve le bond 802.3ad (tous espaces de noms) et affiche /proc/net/bonding/<bond>.
_m07_e40_bond='
for ns in "" $(ip netns list 2>/dev/null | awk "{ print \$1 }"); do
  if [ -n "$ns" ]; then x="ip netns exec $ns"; else x=""; fi
  for b in $($x sh -c "ls /proc/net/bonding 2>/dev/null"); do
    if $x grep -q "802.3ad" "/proc/net/bonding/$b"; then $x cat "/proc/net/bonding/$b"; exit 0; fi
  done
done
exit 1'
_m07_e40_etat="$(_m07x_sur net01 "$_m07_e40_bond" 2>/dev/null)"

check_cmd "net01 : un bond Linux en mode 802.3ad existe" bash -c 'grep -q "802.3ad" <<<"$1"' _ "$_m07_e40_etat"
check_cmd "net01 : l'agrégateur actif compte au moins deux ports" bash -c '
  n="$(awk '\''/^Active Aggregator Info/ { a = 1 } a && /Number of ports:/ { print $NF; exit }'\'' <<<"$1")"
  [ -n "$n" ] && [ "$n" -ge 2 ]' _ "$_m07_e40_etat"
check_cmd "net01 : le partenaire LACP est connu (adresse non nulle)" bash -c '
  grep -E "Partner Mac Address" <<<"$1" | head -n 1 | grep -vq "00:00:00:00:00:00"' _ "$_m07_e40_etat"
check_cmd "net01 : tous les membres du bond sont « MII Status: up »" bash -c '
  [ "$(grep -c "^Slave Interface" <<<"$1")" -ge 2 ] &&
  ! awk '\''/^Slave Interface/ { s = 1 } s && /^MII Status:/ { print; s = 0 }'\'' <<<"$1" | grep -qv up' _ "$_m07_e40_etat"
check_cmd "net01 : Open vSwitch négocie LACP (lacp/show « negotiated »)" _m07x_ok net01 \
  'ovs-appctl lacp/show | grep -q negotiated && [ -n "$(ovs-vsctl --bare --columns=name find port lacp=active)" ]'
check_cmd "panne M07-E40 close (lab/bin/break 07 40 --annuler après réparation)" _m07x_aucune_panne_active E40
