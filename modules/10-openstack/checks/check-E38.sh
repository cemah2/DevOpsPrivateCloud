# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E38.sh — M10-E38 « Panne : le volume ne s'attache pas » : chaîne Cinder → Ceph → libvirt
# saine (services Cinder, droits de client.cinder, moniteurs de cinder-volume, secret libvirt des
# calculs identique à la configuration Kolla, comparé par empreinte) ; le volume de test, s'il
# existe, est attaché. Lecture seule.
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant

# shellcheck source=_m10-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-expert.sh"

title "M10-E38 — Les volumes s'attachent"
require_cmd openstack jq ssh

for _m10_e38_b in cinder-volume cinder-backup; do
  check_cmd "$_m10_e38_b : activé et joignable" \
    bash -c 'timeout 60 openstack --os-cloud "$1" volume service list --service "$2" -f json 2>/dev/null | jq -e "length > 0 and all(.[]; .Status == \"enabled\" and .State == \"up\")" >/dev/null' \
    _ "$_m10x_cloud_admin" "$_m10_e38_b"
done
check_cmd "$_m10x_ctl : cinder_volume en service" _m10x_ctr_sain "$_m10x_ctl" cinder_volume
check_ssh "$_m10x_ctl : ceph.conf de cinder-volume désigne les moniteurs de ceph-par1 (10.10.30.51-54)" "$_m10x_ctl" \
  'sudo -n grep -E "^[[:space:]]*mon[_ ]host[[:space:]]*=" /etc/kolla/cinder-volume/ceph/ceph.conf | grep -Eq "10\.10\.30\.5[1-4]([^0-9]|$)"'
check_output "ceph-par1 : client.cinder peut écrire dans le pool volumes" 'profile rbd pool=volumes' \
  _m10x_ceph auth get client.cinder
check_output "ceph-par1 : client.cinder peut écrire dans le pool vms et lire images" 'pool=vms.*pool=images|pool=images.*pool=vms' \
  _m10x_ceph auth get client.cinder
for _m10_e38_h in "${_m10x_cmps[@]}"; do
  check_ssh "$_m10_e38_h : secret libvirt de client.cinder identique à la configuration Kolla" "$_m10_e38_h" '
    d=/etc/kolla/nova-libvirt/secrets
    f=$(sudo -n grep -l ceph-persistent-cinder "$d"/*.xml 2>/dev/null | head -n 1)
    [ -n "$f" ] || exit 1
    u=$(basename "$f" .xml)
    a=$(sudo -n docker exec nova_libvirt virsh -q secret-get-value "$u" 2>/dev/null | tr -d "[:space:]" | sha256sum)
    b=$(sudo -n cat "$d/$u.base64" | tr -d "[:space:]" | sha256sum)
    [ "$a" = "$b" ]'
done

if _m10x_osp volume show m10-e38-vol -f value -c id >/dev/null 2>&1; then
  check_output "volume de test m10-e38-vol attaché (in-use)" '^in-use$' _m10x_osp volume show m10-e38-vol -f value -c status
else
  skip "volume de test m10-e38-vol" "absent (panne non injectée ou déjà close)"
fi
check_cmd "panne M10-E38 close (lab/bin/break 10 38 --annuler après réparation)" _m10x_aucune_panne_active E38
