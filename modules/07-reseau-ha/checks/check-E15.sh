# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E15.sh — M07-E15 : Jumbo frames sur les réseaux de stockage
# À lancer depuis adm01. Lecture seule (MTU lus, pings sans fragmentation).

# shellcheck source=_m07-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-operationnel.sh"

title "M07-E15 — Jumbo frames sur les réseaux de stockage"
require_cmd jq

# --- pve01 : pont et zone ----------------------------------------------------------------------------------
check_output "pve01 : vmbr1 en MTU 9000" '^9000$' _m07o_mtu "$_M07O_PVE" vmbr1
check_output "pve01 : vmbr0 inchangé (1500)" '^1500$' _m07o_mtu "$_M07O_PVE" vmbr0
# La zone peut porter « mtu 9000 » ou rien (selon ce que fait l'option pour une zone VLAN : corrigé) ;
# jamais une valeur plus petite, qui plafonnerait toutes les VNets.
check_output "pve01 : zone SDN lab sans MTU inférieur à 9000" '^(9000|aucun)$' bash -c \
  'jq -r ".mtu // \"aucun\"" <<<"$1" 2>/dev/null || true' _ \
  "$(remote "$_M07O_PVE" 'pvesh get /cluster/sdn/zones/lab --output-format json' 2>/dev/null || true)"
check_output "pve01 : la VNet vstopub (VLAN 30) accepte 9000" '^9000$' _m07o_mtu "$_M07O_PVE" vstopub

# --- gw01 : seul le VLAN 30 (et le trunk) passent à 9000 -------------------------------------------------
check_output "gw01 : ens19 (trunk) en 9000" '^9000$' _m07o_mtu gw01 ens19
check_output "gw01 : ens19.30 (STOR-PUB) en 9000" '^9000$' _m07o_mtu gw01 ens19.30
for _m07o_v in 10 20 40 50 52 60 70 99; do
  check_output "gw01 : ens19.$_m07o_v reste en 1500" '^1500$' _m07o_mtu gw01 "ens19.$_m07o_v"
done
check_output "gw01 : carte net1 de la VM 1000 en mtu=9000" '^net1:.*mtu=9000' _m07o_vm_config 1000

# --- VMs de test ---------------------------------------------------------------------------------------------
for _m07o_h in srv01:2075 srv02:2076; do
  check_output "${_m07o_h%%:*} : cartes Proxmox des VLAN 30 et 31 en mtu=9000" '^2$' bash -c \
    'grep -E "^net[0-9]+:.*bridge=(vstopub|vstoclu).*mtu=9000" <<<"$1" | wc -l' _ "$(_m07o_vm_config "${_m07o_h#*:}")"
done
check_ssh "srv01 : interface du VLAN 30 en 9000 avec 10.10.30.250" srv01 \
  'i=$(ip -o -4 addr show | awk "/ 10\.10\.30\.250\// {print \$2}"); [ -n "$i" ] && [ "$(cat /sys/class/net/$i/mtu)" = 9000 ]'
check_ssh "srv02 : interface du VLAN 31 en 9000 avec 10.10.31.251" srv02 \
  'i=$(ip -o -4 addr show | awk "/ 10\.10\.31\.251\// {print \$2}"); [ -n "$i" ] && [ "$(cat /sys/class/net/$i/mtu)" = 9000 ]'
check_ssh "srv01 → srv02 (VLAN 31) : 9000 octets sans fragmentation" srv01 \
  'ping -c 2 -W 2 -M do -s 8972 10.10.31.251 >/dev/null'
check_ssh "srv01 → gw01 (10.10.30.1) : 9000 octets sans fragmentation" srv01 \
  'ping -c 2 -W 2 -M do -s 8972 10.10.30.1 >/dev/null'

# --- Rien n'a bougé ailleurs -------------------------------------------------------------------------------
check_cmd "adm01 : toujours en 1500" bash -c '[ "$(cat /sys/class/net/"$(ip -o route get 10.10.20.10 | sed -n "s/.* dev \([^ ]*\).*/\1/p")"/mtu)" = 1500 ]'
check_ssh "dns01 : toujours en 1500" dns01 \
  '[ "$(cat /sys/class/net/"$(ip -o route get 10.10.10.10 | sed -n "s/.* dev \([^ ]*\).*/\1/p")"/mtu)" = 1500 ]'
check_output "plateforme/medisphere : fiche CHG-825 sur main" 'CHG-825' \
  _m07o_cherche_main "$_M07O_PROJET_DOC" '^docs/socle/changements/CHG-825'
