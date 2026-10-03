# shellcheck shell=bash
# check-E47.sh — M00-E47 « Suivre un paquet de bout en bout » : compte rendu présent et
# aucun outil de traçage laissé actif sur le lab.
title "M00-E47 — Suivre un paquet de bout en bout"

_wb_depot="${WB_DEPOT:-$HOME/medisphere}"
_wb_cr="$_wb_depot/docs/socle/analyses/trace-paquet.md"

check_cmd "compte rendu présent (docs/socle/analyses/trace-paquet.md)" test -s "$_wb_cr"
check_output "compte rendu : interface tap de adm01 observée" 'tap1001i0' cat "$_wb_cr"
check_output "compte rendu : trunk côté gw01 observé (étiquettes 802.1Q)" '(802\.1Q|vlan 10|ethertype 802)' cat "$_wb_cr"
check_output "compte rendu : entrée conntrack analysée" '(conntrack|ASSURED|src=10\.10\.10\.10)' cat "$_wb_cr"
check_output "compte rendu : trace nftables exploitée" '(nftrace|monitor trace|trace id)' cat "$_wb_cr"
check_output "compte rendu : réponses aux questions d'analyse" '^## Réponses' cat "$_wb_cr"
check_ssh "gw01 : aucune règle de traçage nftables laissée en place" gw01 "! sudo -n nft list ruleset | grep -q nftrace"
check_ssh "gw01 : aucune capture tcpdump oubliée" gw01 "! pgrep -x tcpdump >/dev/null"
check_ssh "pve01 : aucune capture tcpdump oubliée" "$WB_PVE_HOST" "! pgrep -x tcpdump >/dev/null"
