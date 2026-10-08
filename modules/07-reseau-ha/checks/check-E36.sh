# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E36.sh — M07-E36 « Panne : Lyon ne joint plus Paris » : tunnel wg2 vivant, routage
# cryptographique et routage IP cohérents, politique d'annonce respectée. Lecture seule.

# shellcheck source=_m07-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-expert.sh"

title "M07-E36 — Raccordement de LYO1"
require_cmd ssh jq

check_cmd "lyo-pc01 joint la passerelle du VLAN 20 de PAR1 (10.10.20.1)" \
  _m07x_ok lyo-pc01 'ping -n -c 2 -W 2 10.10.20.1'
check_cmd "lyo-gw01 : poignée de main WireGuard récente sur wg2 (moins de 3 min)" _m07x_ok lyo-gw01 '
  t="$(wg show wg2 latest-handshakes | awk "{ print \$2 }" | sort -n | tail -n 1)"
  [ -n "$t" ] && [ "$t" -gt 0 ] && [ $(( $(date +%s) - t )) -lt 180 ]'
check_cmd "lyo-gw01 : les AllowedIPs du pair couvrent PAR1 (10.10.20.1)" _m07x_ok lyo-gw01 '
  wg show wg2 allowed-ips | python3 -c "
import ipaddress, sys
a = ipaddress.ip_address(\"10.10.20.1\")
sys.exit(0 if any(a in ipaddress.ip_network(p, strict=False) for l in sys.stdin for p in l.split()[1:] if \"/\" in p) else 1)"'
check_cmd "lyo-gw01 : la route vers 10.10.20.1 passe par wg2" _m07x_ok lyo-gw01 \
  "ip -o route get 10.10.20.1 | grep -q ' dev wg2 '"
check_cmd "lyo-gw01 : relais IPv4 actif (net.ipv4.ip_forward = 1)" _m07x_ok lyo-gw01 \
  '[ "$(sysctl -n net.ipv4.ip_forward)" = 1 ]'
_m07_e36_pas_force() { ! _m07x_sysctl_force lyo-gw01 net.ipv4.ip_forward 0; }
check_cmd "lyo-gw01 : aucun fichier sysctl ne désactive le relais au prochain démarrage" _m07_e36_pas_force
_m07_e36_p="$(_m07x_pairs lyo-gw01 65000)"
check_cmd "lyo-gw01 : session BGP avec la bordure (AS 65000) établie, routes de PAR1 reçues" \
  bash -c 'awk '\''$2 == "Established" && $4 > 0 { ok = 1 } END { exit !ok }'\'' <<<"$1"' _ "$_m07_e36_p"
check_cmd "lyo-gw01 : le réseau MGMT de PAR1 (10.10.10.0/24) reste inaccessible par le tunnel" \
  _m07x_ok lyo-gw01 "! ip -o route get 10.10.10.10 | grep -q ' dev wg2 '"
check_cmd "panne M07-E36 close (lab/bin/break 07 36 --annuler après réparation)" _m07x_aucune_panne_active E36
