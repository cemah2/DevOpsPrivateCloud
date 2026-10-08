# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E27.sh — M07-E27 « Basculer sans couper les connexions : conntrackd »
# Lecture seule : gw01/gw02 (admin + sudo -n ; conntrackd -s / -e ne font que lire), dépôt de doc.

# shellcheck source=_m07-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-production.sh"

title "M07-E27 — Basculer sans couper les connexions : conntrackd"
require_cmd ssh
_m07p_charger_adresses gw01 gw02
_m07_s="$(_m07p_secours)"

title "Service et configuration"
for _m07_h in gw01 gw02; do
  case "$_m07_h" in gw01) _m07_l=10.10.10.2 _m07_p=10.10.10.3 ;; *) _m07_l=10.10.10.3 _m07_p=10.10.10.2 ;; esac
  check_ssh "$_m07_h : conntrackd actif et activé" "$_m07_h" 'systemctl is-active -q conntrackd && systemctl is-enabled -q conntrackd'
  check_ssh "$_m07_h : mode FTFW, UDP de $_m07_l vers $_m07_p, port 3780, sur ens19.10" "$_m07_h" "
    c=\$(cat /etc/conntrackd/conntrackd.conf) || exit 1
    grep -Eq '^[[:space:]]*Mode FTFW' <<<\"\$c\" &&
    grep -Eq '^[[:space:]]*UDP[[:space:]]*\\{' <<<\"\$c\" &&
    grep -Eq '^[[:space:]]*IPv4_address[[:space:]]+${_m07_l//./\\.}\$' <<<\"\$c\" &&
    grep -Eq '^[[:space:]]*IPv4_Destination_Address[[:space:]]+${_m07_p//./\\.}\$' <<<\"\$c\" &&
    grep -Eq '^[[:space:]]*Port[[:space:]]+3780\$' <<<\"\$c\" &&
    grep -Eq '^[[:space:]]*Interface[[:space:]]+ens19\\.10\$' <<<\"\$c\""
  check_ssh "$_m07_h : configuration générée par Ansible" "$_m07_h" 'grep -qi "ansible" /etc/conntrackd/conntrackd.conf'
  check_ssh "$_m07_h : conntrackd répond sur son socket de contrôle" "$_m07_h" 'sudo -n conntrackd -s >/dev/null'
  check_ssh_output "$_m07_h : UDP 3780 accepté depuis les seules passerelles sur le VLAN 10" "$_m07_h" \
    'iifname "ens19\.10" ip saddr \{ 10\.10\.10\.2, 10\.10\.10\.3 \} udp dport 3780 accept' 'sudo -n nft list chain inet filter input'
  check_ssh "$_m07_h : la transition pilote conntrackd (BORDURE_CONNTRACKD=1, ordre -c -f -R -B)" "$_m07_h" '
    grep -q "^BORDURE_CONNTRACKD=1" /etc/bordure/transition.conf &&
    awk "/MASTER\\)/ {m=1} m && /ctd -c/ {c=NR} m && /ctd -f/ {f=NR} m && /ctd -R/ {r=NR} m && /ctd -B/ {b=NR} /;;/ {m=0} END {exit !(c && c < f && f < r && r < b)}" /usr/local/sbin/bordure-transition'
done

title "Synchronisation effective"
if [[ -n "$_m07_s" ]]; then
  check_ssh "$_m07_s (secours) : cache externe non vide (connexions du maître reçues)" "$_m07_s" \
    '[ "$(sudo -n conntrackd -e 2>/dev/null | grep -c .)" -gt 0 ]'
else
  check_cmd "une passerelle de secours identifiable (pas de maître unique)" false
fi
_m07_loose() {
  local a b
  a="$(remote gw01 'sysctl -n net.netfilter.nf_conntrack_tcp_loose' 2>/dev/null)" || return 1
  b="$(remote gw02 'sysctl -n net.netfilter.nf_conntrack_tcp_loose' 2>/dev/null)" || return 1
  [[ -n "$a" && "$a" == "$b" ]] && remote gw01 'grep -rqs "nf_conntrack_tcp_loose" /etc/sysctl.d/'
}
check_cmd "nf_conntrack_tcp_loose identique sur les deux passerelles et fixé par le code (sysctl.d)" _m07_loose

title "Mesures"
check_cmd "docs/socle/tests/bascules.md : section conntrackd avec les trois flux" bash -c \
  'f="$1/docs/socle/tests/bascules.md"; grep -qi "conntrackd" "$f" && grep -qiE "loose" "$f" && grep -qiE "ssh" "$f"' _ "$_M07P_DEPOT"
