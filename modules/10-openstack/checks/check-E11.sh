# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E11.sh — M10-E11 : Cinder : volumes, types, snapshots, sauvegardes
# À lancer depuis adm01. Lecture seule : API OpenStack, virsh dumpxml sur le calcul de e11-vm.

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E11 — Cinder : volumes, types, snapshots, sauvegardes"
require_cmd openstack jq

check_output "le type de volume par défaut est ceph-standard" '^ceph-standard$' \
  _m10o_os volume type list --default -f value -c Name
check_output "ceph-standard désigne le backend rbd-1" "volume_backend_name='?rbd-1" \
  _m10o_os volume type show -f value -c properties ceph-standard
_m10o_qos="$(_m10o_os volume qos show -f json qos-500iops || true)"
check_cmd "qos-500iops : consommateur front-end, 500 IOPS au total" \
  jq -e '.consumer == "front-end" and ((.properties // .specs) | tostring | test("total_iops_sec.{0,6}500"))' <<<"$_m10o_qos"
check_cmd "qos-500iops : associée au type ceph-iops-limite" \
  jq -e '.associations | tostring | test("ceph-iops-limite")' <<<"$_m10o_qos"

_m10o_v="$(_m10o_volume vol-essai)"
_m10o_vm="$(_m10o_serveur e11-vm)"
_m10o_vm_id="$(jq -r '.id // empty' <<<"$_m10o_vm" 2>/dev/null || true)"
check_cmd "vol-essai : 20 Go, type ceph-iops-limite" \
  jq -e '.size == 20 and .type == "ceph-iops-limite"' <<<"$_m10o_v"
check_cmd "vol-essai : attaché à e11-vm" \
  jq -e --arg id "$_m10o_vm_id" '$id != "" and .status == "in-use" and (.attachments | tostring | contains($id))' <<<"$_m10o_v"

_m10o_snap_id="$(_m10o_os volume snapshot list --all-projects --name snap-essai -f value -c ID | head -n 1 || true)"
check_cmd "snap-essai existe (instantané de vol-essai)" test -n "$_m10o_snap_id"
check_cmd "vol-clone existe et provient de snap-essai" \
  jq -e --arg s "$_m10o_snap_id" '$s != "" and .snapshot_id == $s' <<<"$(_m10o_volume vol-clone)"

_m10o_sauv() { _m10o_os volume backup list --all-projects --name "$1" -f value -c ID | head -n 1 || true; }
_m10o_s1="$(_m10o_sauv sauv-essai)"
_m10o_s2="$(_m10o_sauv sauv-essai-inc)"
_m10o_sauv_json() { [[ -n "$1" ]] && _m10o_os volume backup show -f json "$1"; }
check_cmd "sauv-essai : disponible" \
  jq -e '.status == "available"' <<<"$(_m10o_sauv_json "$_m10o_s1" || true)"
check_cmd "sauv-essai-inc : disponible et incrémentale" \
  jq -e '.status == "available" and .is_incremental == true' <<<"$(_m10o_sauv_json "$_m10o_s2" || true)"
check_cmd "vol-restaure existe" jq -e '.id != null' <<<"$(_m10o_volume vol-restaure)"

_m10o_hote="$(jq -r '.["OS-EXT-SRV-ATTR:host"] // empty' <<<"$_m10o_vm" 2>/dev/null || true)"
_m10o_nom="$(jq -r '.["OS-EXT-SRV-ATTR:instance_name"] // empty' <<<"$_m10o_vm" 2>/dev/null || true)"
if [[ -n "$_m10o_hote" && -n "$_m10o_nom" ]]; then
  check_ssh_output "e11-vm ($_m10o_hote) : la définition libvirt limite le disque à 500 IOPS" "${_m10o_hote%%.*}" \
    '<total_iops_sec>500</total_iops_sec>' "sudo -n docker exec nova_libvirt virsh dumpxml $_m10o_nom"
else
  _ko "e11-vm : instance introuvable (hôte ou nom libvirt inconnus)"
fi
