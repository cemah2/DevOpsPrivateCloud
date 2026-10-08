# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E19.sh — M07-E19 : Routage dynamique à travers le tunnel
# À lancer depuis adm01, lyo-gw01 et lyo-pc01 démarrées. Lecture seule.

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E19 — Routage dynamique à travers le tunnel"
require_cmd jq

_m07o_resume="$(_m07o_vtysh gw01 'show bgp ipv4 unicast summary json')"
check_output "gw01 : session avec lyo-gw01 (10.255.2.2, AS 65030) établie" '^Established 65030$' \
  jq -r '.peers["10.255.2.2"] | "\(.state) \(.remoteAs)"' <<<"$_m07o_resume"
check_output "lyo-gw01 : AS 65030, session avec la bordure établie" '^65030 Established$' bash -c \
  'jq -r "\"\(.as) \(.peers[\"10.255.2.1\"].state // \"absent\")\"" <<<"$1" 2>/dev/null || true' _ \
  "$(_m07o_vtysh lyo-gw01 'show bgp ipv4 unicast summary json')"
check_ssh "gw01 : 10.30.0.0/16 installé par BGP" gw01 'ip route show proto bgp 10.30.0.0/16 | grep -q "via 10\.255\.2\.2"'
check_ssh "lyo-gw01 : 10.10.20.0/24 et 10.10.70.0/24 installés par BGP" lyo-gw01 \
  'ip route show proto bgp | grep -q "^10\.10\.20\.0/24" && ip route show proto bgp | grep -q "^10\.10\.70\.0/24"'
check_ssh "lyo-gw01 : MGMT (10.10.10.0/24) n'est PAS appris" lyo-gw01 \
  '! ip route show proto bgp | grep -q "^10\.10\.10\."'
check_ssh "lyo-gw01 : rien d'autre que des réseaux de 10.10.0.0/16 appris de PAR1" lyo-gw01 \
  '! ip route show proto bgp | grep -vq "^10\.10\."'
for _m07o_h in gw01 lyo-gw01; do
  check_ssh "$_m07o_h : plus de route statique posée par wg-quick (ni PostUp, ni Table automatique)" "$_m07o_h" \
    '! sudo -n grep -Eiq "^[[:space:]]*PostUp[[:space:]]*=.*ip route" /etc/wireguard/wg2.conf && sudo -n grep -Eiq "^[[:space:]]*Table[[:space:]]*=[[:space:]]*off" /etc/wireguard/wg2.conf'
done
check_ssh "lyo-gw01 : AllowedIPs de PAR1 couvrent ce que BGP installe" lyo-gw01 \
  'a=$(sudo -n wg show wg2 allowed-ips); grep -q "10\.10\.20\.0/24" <<<"$a" && grep -q "10\.10\.70\.0/24" <<<"$a"'
check_ssh "lyo-pc01 : joint toujours dns01 depuis le LAN de l'agence" lyo-pc01 \
  'dig +short +time=2 +tries=1 -b 10.30.10.10 @10.10.20.10 dns01.par1.medisphere.internal A | grep -q "^10\.10\.20\.10$"'
check_output "gw01 : port 179 ouvert sur wg2 pour 10.255.2.2 seulement" \
  'iifname "wg2" ip saddr 10\.255\.2\.2 tcp dport 179 accept' _m07o_nft_gw01 input
check_output "gw01 : plafond de préfixes sur la session LYO1" 'neighbor 10\.255\.2\.2 maximum-prefix' \
  _m07o_vtysh gw01 'show running-config'
