# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
# check-E19.sh — M11-E19 « Panne : le serveur ne démarre pas sur le réseau » : Kea sert le VLAN 60
# (configuration valide, serveur suivant = pxe01, classes BIOS et UEFI) sur dns01 et dns02, relais du
# VLAN 60 (et du VLAN 99) actif, chargeurs lisibles en TFTP, panne close. Lecture seule.

# shellcheck source=_m11-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-expert.sh"

title "M11-E19 — Démarrage réseau du VLAN 60"
require_cmd ssh jq

for _m11_e19_h in dns01 dns02; do
  if [[ "$_m11_e19_h" == dns02 ]] && ! remote dns02 true >/dev/null 2>&1; then
    skip "dns02 : Kea" "dns02 injoignable ou absent"
    continue
  fi
  _m11_e19_c="$(_m11x_kea_conf "$_m11_e19_h")" || true
  check_ssh "$_m11_e19_h : Kea actif, configuration acceptée par kea-dhcp4 -t" "$_m11_e19_h" \
    'systemctl is-active -q isc-kea-dhcp4-server && sudo -n kea-dhcp4 -t /etc/kea/kea-dhcp4.conf'
  check_cmd "$_m11_e19_h : sous-réseau 10.10.60.0/24 servi" grep -q '10\.10\.60\.0/24' <<<"$_m11_e19_c"
  check_cmd "$_m11_e19_h : pxe01 (10.10.60.10) désigné, aucun autre serveur suivant dans le VLAN 60" \
    bash -c 'grep -q "10\.10\.60\.10" <<<"$1" && ! grep -Eq "\"next-server\"[[:space:]]*:[[:space:]]*\"10\.10\.60\.([02-9]|1[1-9]|[2-9][0-9]|[0-9]{3})\"" <<<"$1"' _ "$_m11_e19_c"
  check_cmd "$_m11_e19_h : classe BIOS (option 93 = 0x0000) et classe UEFI x64 (0x0007 ou 0x0009)" \
    bash -c 'grep -Eq "option\[93\]\.hex[[:space:]]*==[[:space:]]*0x0000" <<<"$1" && grep -Eq "option\[93\]\.hex[[:space:]]*==[[:space:]]*0x000[79]" <<<"$1"' _ "$_m11_e19_c"
done
check_cmd "relais DHCP du VLAN 60 actif sur au moins une passerelle" _m11x_relais_vlan60
check_cmd "relais DHCP du VLAN 99 toujours actif (VLAN sandbox non touché)" _m11x_relais_vlan99
check_ssh "pxe01 : tftpd-hpa actif" pxe01 'systemctl is-active -q tftpd-hpa'
check_cmd "pxe01 : undionly.kpxe et ipxe.efi lisibles en TFTP sur 10.10.60.10" _m11p_tftp_ok undionly.kpxe ipxe.efi
check_cmd "panne M11-E19 close (lab/bin/break 11 19 --annuler après réparation)" _m11p_aucune_panne_active E19
