# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E35.sh — M10-E35 « Panne : No valid host was found » : le calcul est planifiable (services
# nova-compute actifs, réservations et ratios raisonnables, gabarits et images sans exigence
# impossible). Lecture seule.

# shellcheck disable=SC2016  # scripts bash -c : arguments passés en $1, $2

# shellcheck source=_m10-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-expert.sh"

title "M10-E35 — Le calcul est planifiable"
require_cmd openstack jq ssh

for _m10_e35_h in "${_m10x_cmps[@]}"; do
  check_output "$_m10_e35_h : nova-compute activé et joignable (enabled up)" '^enabled up$' \
    _m10x_etat_calcul "$_m10_e35_h"
  check_cmd "$_m10_e35_h : mémoire réservée à l'hôte ≤ 2048 Mio (nova.conf de nova_compute)" \
    bash -c 'v="$1"; [ -z "$v" ] || [ "$v" -le 2048 ]' _ \
    "$(_m10x_ini "$_m10_e35_h" /etc/kolla/nova-compute/nova.conf DEFAULT reserved_host_memory_mb)"
  check_cmd "$_m10_e35_h : ratios d'allocation RAM et CPU ≥ 1 s'ils sont fixés" \
    python3 -c 'import sys; sys.exit(0 if all((not v) or float(v) >= 1 for v in sys.argv[1:]) else 1)' \
    "$(_m10x_ini "$_m10_e35_h" /etc/kolla/nova-compute/nova.conf DEFAULT ram_allocation_ratio)" \
    "$(_m10x_ini "$_m10_e35_h" /etc/kolla/nova-compute/nova.conf DEFAULT cpu_allocation_ratio)"
done

for _m10_e35_g in m1.petit m1.moyen m1.grand; do
  check_cmd "gabarit $_m10_e35_g présent, sans trait exigé (trait:…=required)" \
    bash -c 'j="$(timeout 60 openstack --os-cloud "$1" flavor show "$2" -f json 2>/dev/null)" && [ -n "$j" ] \
      && ! jq -e "(.properties // {}) | to_entries | map(select((.key | startswith(\"trait:\")) and .value == \"required\")) | length > 0" <<<"$j" >/dev/null' \
    _ "$_m10x_cloud_admin" "$_m10_e35_g"
done

check_cmd "images publiques : aucune n'exige une architecture autre que x86_64" \
  bash -c 'for id in $(timeout 60 openstack --os-cloud "$1" image list --public -f value -c ID 2>/dev/null); do
      a="$(timeout 60 openstack --os-cloud "$1" image show "$id" -f json 2>/dev/null | jq -r ".properties.hw_architecture // empty")"
      [ -z "$a" ] || [ "$a" = x86_64 ] || exit 1
    done' _ "$_m10x_cloud_admin"
check_cmd "aucune instance en ERROR dans le projet plateforme" \
  bash -c '[ "$(timeout 60 openstack --os-cloud "$1" server list --status ERROR -f value -c ID 2>/dev/null | wc -l)" -eq 0 ]' _ "$_m10x_cloud_projet"
check_cmd "panne M10-E35 close (lab/bin/break 10 35 --annuler après réparation)" _m10x_aucune_panne_active E35
