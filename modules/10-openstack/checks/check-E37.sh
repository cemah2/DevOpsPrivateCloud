# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M10-E37 « Panne : l'instance ignore sa configuration » : service de métadonnées
# sain de bout en bout (agents OVN de métadonnées sur les calculs, nova-metadata sur osctl01, secret
# partagé identique des deux côtés, comparé par empreinte) ; la sonde, si elle existe, a reçu sa
# clé. Lecture seule.

# shellcheck disable=SC2016  # scripts bash -c : arguments passés en $1, $2

# shellcheck source=_m10-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-expert.sh"

title "M10-E37 — Les instances reçoivent leurs métadonnées"
require_cmd openstack jq ssh

check_cmd "$_m10x_ctl : nova_metadata en service" _m10x_ctr_sain "$_m10x_ctl" nova_metadata
_m10_e37_ref="$(_m10x_ini_empreinte "$_m10x_ctl" /etc/kolla/nova-metadata/nova.conf neutron metadata_proxy_shared_secret)"
check_cmd "$_m10x_ctl : nova-metadata a un secret partagé de proxy" test -n "$_m10_e37_ref"
for _m10_e37_h in "${_m10x_cmps[@]}"; do
  check_cmd "$_m10_e37_h : neutron_ovn_metadata_agent en service" _m10x_ctr_sain "$_m10_e37_h" neutron_ovn_metadata_agent
  check_cmd "$_m10_e37_h : agent de métadonnées vivant pour Neutron" \
    bash -c 'timeout 60 openstack --os-cloud "$1" network agent list --host "$2" -f json 2>/dev/null | jq -e "map(select(.\"Agent Type\" | test(\"Metadata\"))) | length > 0 and all(.[]; .Alive == true or .Alive == \":-)\")" >/dev/null' \
    _ "$_m10x_cloud_admin" "$_m10_e37_h"
  check_cmd "$_m10_e37_h : secret partagé identique à celui de nova-metadata" \
    test -n "$_m10_e37_ref" -a "$_m10_e37_ref" = \
    "$(_m10x_ini_empreinte "$_m10_e37_h" /etc/kolla/neutron-ovn-metadata-agent/neutron_ovn_metadata_agent.ini DEFAULT metadata_proxy_shared_secret)"
done

_m10_e37_fip="$(_m10x_fip_port m10-e37-port)"
if [[ -n "$_m10_e37_fip" ]] && _m10x_osp server show m10-e37-sonde -f value -c id >/dev/null 2>&1; then
  check_cmd "sonde m10-e37-sonde : sa clé SSH a été installée (connexion par clé sur $_m10_e37_fip)" _m10x_ssh_sonde "$_m10_e37_fip"
else
  skip "sonde m10-e37-sonde" "absente (panne non injectée ou déjà close)"
fi
check_cmd "panne M10-E37 close (lab/bin/break 10 37 --annuler après réparation)" _m10x_aucune_panne_active E37
