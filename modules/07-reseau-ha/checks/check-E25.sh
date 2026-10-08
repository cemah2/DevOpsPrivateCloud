# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E25.sh — M07-E25 « VRRP sur les passerelles du lab »
# Lecture seule : gw01/gw02 (admin + sudo -n), adm01 (chrony), DNS, API NetBox et GitLab.

# shellcheck source=_m07-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-production.sh"

title "M07-E25 — VRRP sur les passerelles du lab"
require_cmd jq dig ssh
_m07p_charger
_m07p_charger_adresses gw01 gw02

title "Adresses : .2, .3 et une VIP .1 par VLAN"
for _m07_v in "${_M07P_VLANS[@]}"; do
  check_cmd "VLAN $_m07_v : gw01 porte .2" _m07p_porte gw01 "10.10.$_m07_v.2"
  check_cmd "VLAN $_m07_v : gw02 porte .3" _m07p_porte gw02 "10.10.$_m07_v.3"
  check_cmd "VLAN $_m07_v : VIP 10.10.$_m07_v.1 portée par une seule passerelle" _m07p_vip_unique "10.10.$_m07_v.1" gw01 gw02
done
check_ssh "gw01 : aucune .1 configurée en statique (/etc/network/interfaces)" gw01 \
  '! grep -Eq "^[[:space:]]*address[[:space:]]+10\.10\.[0-9]+\.1/" /etc/network/interfaces /etc/network/interfaces.d/* 2>/dev/null'
check_ssh "gw02 : aucune .1 configurée en statique (netplan)" gw02 \
  '! sudo -n grep -rEq "10\.10\.[0-9]+\.1/24" /etc/netplan/'
# _m07_vlans_ensemble — les neuf VIP des VLAN sont sur la même passerelle (la VIP WAN : M07-E26).
_m07_vlans_ensemble() {
  local m v
  m="$(_m07p_maitre)"
  [[ -n "$m" ]] || return 1
  for v in "${_M07P_VLANS[@]}"; do
    [[ "$(_m07p_porteurs "10.10.$v.1" gw01 gw02)" == "$m" ]] || return 1
  done
}
check_cmd "toutes les VIP des VLAN sur la même passerelle (groupe de synchronisation)" _m07_vlans_ensemble

title "keepalived"
for _m07_h in gw01 gw02; do
  check_ssh "$_m07_h : keepalived actif" "$_m07_h" 'systemctl is-active -q keepalived'
  check_ssh_output "$_m07_h : VRRP version 3" "$_m07_h" '^[[:space:]]*(vrrp_)?version[[:space:]]+3' \
    'sudo -n cat /etc/keepalived/keepalived.conf'
  check_ssh "$_m07_h : une instance par VLAN, VRID = numéro de VLAN, en unicast" "$_m07_h" '
    c=$(sudo -n cat /etc/keepalived/keepalived.conf) || exit 1
    for v in 10 20 30 40 50 52 60 70 99; do
      awk -v v="$v" "/^vrrp_instance/ {i=0} /interface ens19\\.${v}\$/ {i=1} i && /virtual_router_id ${v}\$/ {ok=1} END {exit !ok}" <<<"$c" || exit 1
    done
    [ "$(grep -c "unicast_peer" <<<"$c")" -ge 9 ] && ! grep -q "vrrp_strict" <<<"$c"'
  check_ssh "$_m07_h : groupe de synchronisation BORDURE (9 instances au moins) et script de transition" "$_m07_h" '
    c=$(sudo -n cat /etc/keepalived/keepalived.conf) || exit 1
    grep -q "^vrrp_sync_group BORDURE" <<<"$c" && grep -q "bordure-transition" <<<"$c" &&
    [ "$(awk "/^vrrp_sync_group BORDURE/ {g=1} g && /^}/ {g=0} g && /^[[:space:]]+(VLAN|WAN)[0-9]*[[:space:]]*\$/ {n++} END {print n+0}" <<<"$c")" -ge 9 ]'
done
check_ssh_output "gw01 : priorité 150" gw01 '^[[:space:]]*priority[[:space:]]+150$' 'sudo -n grep -h priority /etc/keepalived/keepalived.conf'
check_ssh_output "gw02 : priorité 100" gw02 '^[[:space:]]*priority[[:space:]]+100$' 'sudo -n grep -h priority /etc/keepalived/keepalived.conf'
_m07_etats() {
  local a b
  a="$(remote gw01 'cat /run/bordure/etat' 2>/dev/null)" || return 1
  b="$(remote gw02 'cat /run/bordure/etat' 2>/dev/null)" || return 1
  [[ "$a:$b" == "MASTER:BACKUP" || "$a:$b" == "BACKUP:MASTER" ]] || return 1
  [[ "$(_m07p_maitre)" == "$([[ "$a" == MASTER ]] && echo gw01 || echo gw02)" ]]
}
check_cmd "/run/bordure/etat : MASTER sur la passerelle qui porte les VIP, BACKUP sur l'autre" _m07_etats

title "Matrice des flux"
for _m07_h in gw01 gw02; do
  check_ssh_output "$_m07_h : VRRP (protocole 112) accepté depuis les passerelles" "$_m07_h" \
    'ip saddr \{ 10\.10\.99\.2, 10\.10\.99\.3 \} meta l4proto (112|vrrp) accept' 'sudo -n nft list chain inet filter input'
done
check_cmd "gw01 et gw02 chargent le même jeu de règles" _m07p_rulesets_identiques

title "Ce qui dépendait de « gw01 = .1 »"
check_dns "DNS : gw01.$_M07P_ZONE → 10.10.10.2" "gw01.$_M07P_ZONE" A '^10\.10\.10\.2$' 10.10.20.10
check_dns "DNS : gw02.$_M07P_ZONE → 10.10.10.3" "gw02.$_M07P_ZONE" A '^10\.10\.10\.3$' 10.10.20.10
_m07_fhrp="$(netbox_api "ipam/fhrp-groups/?protocol=vrrp3&limit=100" 2>/dev/null || true)"
check_cmd "NetBox : groupes FHRP vrrp3 pour les neuf VLAN (identifiant = VRID)" jq -e \
  '[.results[].group_id] as $g | [10,20,30,40,50,52,60,70,99] | all(. as $v | $g | index($v))' <<<"${_m07_fhrp:-null}"
check_ssh "gw01 : relais DHCP avec son adresse propre (10.10.99.2)" gw01 \
  'grep -Ehqs "^[[:space:]]*dhcp-relay=10\.10\.99\.2," /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf'
check_ssh "gw02 : relais DHCP avec son adresse propre (10.10.99.3)" gw02 \
  'grep -Ehqs "^[[:space:]]*dhcp-relay=10\.10\.99\.3," /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf'
check_output "adm01 : sources de temps 10.10.10.2 et 10.10.10.3" '10\.10\.10\.2.*10\.10\.10\.3|10\.10\.10\.3.*10\.10\.10\.2' \
  bash -c 'chronyc -n sources 2>/dev/null | tr "\n" " "'
if _m07p_vm_tourne 2073; then
  check_cmd "BGP : gw01 ↔ leaf01 établie (adresse propre)" _m07p_bgp_etabli gw01 10.10.99.251
  check_cmd "BGP : gw02 ↔ leaf01 établie (adresse propre)" _m07p_bgp_etabli gw02 10.10.99.251
else
  skip "BGP avec leaf01" "maquette arrêtée (VM 2073)"
fi

title "Documentation"
check_cmd "plateforme/medisphere : fiche CHG-855 sur main" _m07p_doc_main docs/socle/changements CHG-855
check_cmd "plateforme/medisphere : RB-071 sur main" _m07p_doc_main docs/socle/runbooks RB-071
