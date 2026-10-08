# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes ($r est une variable jq)
#
# check-E08.sh — M10-E08 : Neutron et OVN : réseaux, routeurs, IP flottantes
# À lancer depuis adm01. Lecture seule : CLI openstack (network/subnet/router/security group/
# server show) avec WB_OS_CLOUD et le cloud medisphere-plateforme (E05), ping et connexion TCP
# vers l'IP flottante, API GitLab en GET.

# shellcheck source=_m10-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-decouverte.sh"

title "M10-E08 — Neutron et OVN : réseaux, routeurs, IP flottantes"
require_cmd jq openstack ping

_m10d_e08_p="$_M10D_CLOUD_PLAT"

# --- 1. Réseau externe ----------------------------------------------------------------------------
_m10d_e08_ext="$(_m10d_os network show ext-net)"
check_cmd "ext-net : externe, flat sur physnet1, MTU 1500" _m10d_jq "$_m10d_e08_ext" \
  '((."router:external" | tostring) | test("^(true|External)$"))
   and ."provider:network_type" == "flat" and ."provider:physical_network" == "physnet1" and .mtu == 1500'
check_cmd "ext-net : non partagé (on n'y branche pas d'instance)" _m10d_jq "$_m10d_e08_ext" '.shared == false'
_m10d_e08_extsn="$(_m10d_os subnet list --network ext-net)"
_m10d_e08_extsnid="$(jq -r '.[0].ID // "absent"' <<<"${_m10d_e08_extsn:-null}" 2>/dev/null || echo absent)"
check_cmd "ext-net : un seul sous-réseau, 10.10.52.0/24" _m10d_jq "$_m10d_e08_extsn" \
  'length == 1 and .[0].Subnet == "10.10.52.0/24"'
check_cmd "Sous-réseau externe : passerelle 10.10.52.1, sans DHCP, allocation 10.10.52.200-249" \
  _m10d_jq "$(_m10d_os subnet show "$_m10d_e08_extsnid")" \
  '.gateway_ip == "10.10.52.1" and .enable_dhcp == false
   and ((.allocation_pools | tostring) | test("10\\.10\\.52\\.200.*10\\.10\\.52\\.249"))
   and ((.allocation_pools | length) == 1)'
check_cmd "plateforme/openstack (main) : playbooks/reseau-externe.yml" \
  _m10d_fichier_main plateforme/openstack playbooks/reseau-externe.yml

# --- 2. Routeur et réseau du projet -------------------------------------------------------------
_m10d_e08_extid="$(jq -r '.id // "absent"' <<<"${_m10d_e08_ext:-null}" 2>/dev/null || echo absent)"
_m10d_e08_snid="$(_m10d_os --os-cloud "$_m10d_e08_p" subnet show sous-reseau-plateforme | jq -r '.id // "absent"' 2>/dev/null || echo absent)"
_m10d_e08_rt="$(_m10d_os --os-cloud "$_m10d_e08_p" router show routeur-plateforme)"
check_cmd "routeur-plateforme : passerelle sur ext-net" _m10d_jq "$_m10d_e08_rt" \
  "(.external_gateway_info | if type == \"string\" then fromjson else . end).network_id == \"$_m10d_e08_extid\""
check_cmd "routeur-plateforme : interface sur sous-reseau-plateforme" _m10d_jq "$_m10d_e08_rt" \
  "(.interfaces_info | tostring) | contains(\"$_m10d_e08_snid\")"
check_cmd "reseau-plateforme : MTU 1442 (Geneve ; 1500 après M10-E12)" \
  _m10d_jq "$(_m10d_os --os-cloud "$_m10d_e08_p" network show reseau-plateforme)" '.mtu == 1442 or .mtu == 1500'

# --- 3. Groupe de sécurité ------------------------------------------------------------------------
_m10d_e08_sg="$(_m10d_os --os-cloud "$_m10d_e08_p" security group show ssh-icmp-admin)"
check_cmd "ssh-icmp-admin : en entrée, seulement TCP 22 et ICMP, depuis 10.10.10.0/24" _m10d_jq "$_m10d_e08_sg" '
  [.rules[] | select(.direction == "ingress")] as $r
  | ($r | length) >= 2
  and ($r | all(.remote_ip_prefix == "10.10.10.0/24"))
  and ($r | all((.protocol == "tcp" and .port_range_min == 22 and .port_range_max == 22) or .protocol == "icmp"))
  and ($r | any(.protocol == "tcp")) and ($r | any(.protocol == "icmp"))'

# --- 4. L'IP flottante de essai01 ------------------------------------------------------------------
_m10d_e08_vm="$(_m10d_os --os-cloud "$_m10d_e08_p" server show essai01)"
_m10d_e08_fip="$(jq -r '.addresses | tostring' <<<"${_m10d_e08_vm:-null}" 2>/dev/null \
  | grep -oE '10\.10\.52\.(2[0-4][0-9])' | head -n 1 || true)"
check_cmd "essai01 : une IP flottante dans 10.10.52.200-249" test -n "$_m10d_e08_fip"
check_cmd "essai01 : groupe ssh-icmp-admin attaché" _m10d_jq "$_m10d_e08_vm" \
  '(.security_groups | tostring) | test("ssh-icmp-admin")'
if [[ -n "$_m10d_e08_fip" ]]; then
  check_ping "adm01 → $_m10d_e08_fip (essai01) : ping" "$_m10d_e08_fip"
  check_port "adm01 → $_m10d_e08_fip:22 (essai01) : SSH" "$_m10d_e08_fip" 22
else
  skip "Ping et SSH vers l'IP flottante" "pas d'IP flottante sur essai01"
fi

# --- 5. Documentation -------------------------------------------------------------------------------
check_cmd "plateforme/medisphere (main) : docs/cloud/reseau-projets.md" \
  _m10d_fichier_main plateforme/medisphere docs/cloud/reseau-projets.md
