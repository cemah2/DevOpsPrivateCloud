# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
# check-E44.sh — M07-E44 « Sous le capot : le voyage d'un paquet » : compte rendu présent, structuré
# et commité ; aucune capture, trace nftables ou suivi conntrack laissé actif. Lecture seule.

# shellcheck source=_m07-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-expert.sh"

title "M07-E44 — Sous le capot : le voyage d'un paquet"
require_cmd ssh git

_m07_e44_depot="${WB_DEPOT:-$HOME/medisphere}"
_m07_e44_cr="$_m07_e44_depot/docs/socle/analyses/voyage-paquet.md"
check_cmd "compte rendu docs/socle/analyses/voyage-paquet.md présent" test -s "$_m07_e44_cr"
check_output "section couche 2 (pont, VLAN, FDB)" '^## .*[Cc]ouche 2' cat "$_m07_e44_cr"
check_output "section couche 3 (routage)" '^## .*[Cc]ouche 3' cat "$_m07_e44_cr"
check_output "section filtrage et suivi des connexions" '^## .*([Ff]iltrage|conntrack)' cat "$_m07_e44_cr"
check_output "section plan de contrôle (VRRP, BGP)" '^## .*[Pp]lan de contr[ôo]le' cat "$_m07_e44_cr"
check_output "section « Réponses aux questions »" '^## Réponses aux questions' cat "$_m07_e44_cr"
check_cmd "extraits cités : bridge fdb, conntrack, nftrace, ip route get, VRRP, BGP" \
  bash -c 'for m in "bridge fdb" conntrack nftrace "ip route get" vrrp bgp; do grep -qi -- "$m" "$1" || exit 1; done' _ "$_m07_e44_cr"
check_cmd "compte rendu commité, sans modification en attente" \
  bash -c 'cd "$1" && git ls-files --error-unmatch docs/socle/analyses/voyage-paquet.md >/dev/null 2>&1 && [ -z "$(git status --porcelain -- docs/socle/analyses)" ]' _ "$_m07_e44_depot"
check_ssh "pve01 : aucune capture tcpdump en cours" "$WB_PVE_HOST" '! pgrep -x tcpdump >/dev/null'
for _m07_e44_gw in gw01 gw02; do
  if [[ "$_m07_e44_gw" == gw02 ]] && ! _m07x_existe gw02; then
    skip "gw02 : traces" "gw02 absente"
    continue
  fi
  check_cmd "$_m07_e44_gw : aucune capture, trace nftables (nft monitor) ni suivi conntrack (-E) en cours" \
    _m07x_ok "$_m07_e44_gw" '! pgrep -x tcpdump >/dev/null && ! pgrep -f "nft monitor" >/dev/null && ! pgrep -f "conntrack -E" >/dev/null'
  check_cmd "$_m07_e44_gw : aucune règle « meta nftrace » restée dans le jeu de règles" _m07x_ok "$_m07_e44_gw" \
    '! nft list ruleset | grep -q nftrace'
done
