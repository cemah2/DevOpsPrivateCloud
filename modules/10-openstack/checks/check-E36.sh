# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M10-E36 « Panne : l'IP flottante ne répond pas » : chemin nord-sud sain (passerelle
# OVN sur osctl01, correspondance physnet1, interface externe dans son pont et active, agents
# vivants) ; si la sonde de la panne existe encore, elle répond depuis adm01. Lecture seule.
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant

# shellcheck source=_m10-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-expert.sh"

title "M10-E36 — Les IP flottantes répondent"
require_cmd openstack jq ssh ping

check_cmd "$_m10x_ctl : ovn_controller en service" _m10x_ctr_sain "$_m10x_ctl" ovn_controller
check_cmd "$_m10x_ctl : openvswitch_vswitchd en service" _m10x_ctr_sain "$_m10x_ctl" openvswitch_vswitchd
check_ssh_output "$_m10x_ctl : le réseau physique physnet1 est relié à un pont (ovn-bridge-mappings)" "$_m10x_ctl" \
  '(^|[",])physnet1:[A-Za-z0-9_-]+' \
  "sudo -n docker exec openvswitch_vswitchd ovs-vsctl get open . external_ids:ovn-bridge-mappings"
check_ssh "$_m10x_ctl : l'interface externe est dans le pont de physnet1 et active" "$_m10x_ctl" '
  p=$(sudo -n docker exec openvswitch_vswitchd ovs-vsctl get open . external_ids:ovn-bridge-mappings | tr -d "\"" | tr "," "\n" | sed -n "s/^physnet1://p" | head -n 1)
  [ -n "$p" ] || exit 1
  i=$(sudo -n docker exec openvswitch_vswitchd ovs-vsctl list-ports "$p" | grep -v "^patch-" | head -n 1)
  [ -n "$i" ] && ip -br link show "$i" | grep -qw UP'
check_cmd "agents réseau : aucun agent mort (openstack network agent list)" \
  bash -c 'j="$(timeout 60 openstack --os-cloud "$1" network agent list -f json 2>/dev/null)" && [ -n "$j" ] && jq -e "length > 0 and all(.[]; .Alive == true or .Alive == \":-)\")" <<<"$j" >/dev/null' _ "$_m10x_cloud_admin"
check_output "ext-net : réseau externe présent" '^True$' _m10x_os network show ext-net -f value -c router:external

_m10_e36_fip="$(_m10x_fip_port m10-e36-port)"
if [[ -n "$_m10_e36_fip" ]]; then
  check_ping "sonde m10-e36-sonde : ping de son IP flottante $_m10_e36_fip depuis adm01" "$_m10_e36_fip"
  check_cmd "sonde m10-e36-sonde : SSH par clé sur $_m10_e36_fip" _m10x_ssh_sonde "$_m10_e36_fip"
else
  skip "sonde m10-e36-sonde" "absente (panne non injectée ou déjà close)"
fi
# Les ressources de test n'existent que tant que la panne est ouverte : ce contrôle se lance
# AVANT --annuler (énoncé). Dans ce cas, la clôture de la panne n'est pas encore attendue.
if [[ -n "$_m10_e36_fip" ]]; then
  skip "panne M10-E36 close" "ressources de test présentes : lance lab/bin/break 10 36 --annuler après ce contrôle vert"
else
  check_cmd "panne M10-E36 close (lab/bin/break 10 36 --annuler après réparation)" _m10x_aucune_panne_active E36
fi
