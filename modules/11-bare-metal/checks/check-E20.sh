# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E20.sh — M11-E20 « Panne : iPXE s'arrête en chemin » : boot.ipxe et scripts par MAC servis en
# HTTPS, lisibles, au format iPXE ; certificat de pxe01 émis par la PKI ; panne close. Lecture seule.

# shellcheck source=_m11-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-expert.sh"

title "M11-E20 — Scripts iPXE servis en HTTPS"
require_cmd curl openssl ssh

_m11_e20_ok() { [[ "$(_m11p_https "$1")" == 0 ]]; }
_m11_e20_ipxe() { [[ "$(_m11p_https_contenu "$1" | head -n 1)" == "#!ipxe" ]]; }

check_cmd "pxe01 : certificat vérifié, chaîne complète émise par l'intermédiaire MédiSphère" _m11p_pki_ok
check_cmd "boot.ipxe servi en HTTPS" _m11_e20_ok /boot.ipxe
check_cmd "boot.ipxe : première ligne « #!ipxe »" _m11_e20_ipxe /boot.ipxe
mapfile -t _m11_e20_mac < <(_m11x_scripts_mac)
check_cmd "pxe01 : au moins un script par MAC (ipxe/mac-*.ipxe)" test "${#_m11_e20_mac[@]}" -ge 1
_m11_e20_both() { _m11_e20_ok "$1" && _m11_e20_ipxe "$1"; }
for _m11_e20_s in "${_m11_e20_mac[@]}"; do
  check_cmd "$_m11_e20_s : servi en HTTPS et au format iPXE" _m11_e20_both "$_m11_e20_s"
done
check_cmd "panne M11-E20 close (lab/bin/break 11 20 --annuler après réparation)" _m11p_aucune_panne_active E20
