# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S08.sh — F3-S08 « Mercredi : le stockage ralentit tout » : Ceph HEALTH_OK, aucun drapeau qui
# bloque la reconstruction, tous les OSD up et in, latence de commit normale, quota du pool RBD qui ne
# bride pas le cluster, disques des VMs Ceph sans limite d'E/S, santé, trace INC-5908. Lecture seule
# (ceph … -f json par sudo -n sur le nœud _admin, qm config sur pve01).

# shellcheck source=_f3-debut.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-debut.sh"

title "F3-S08 — Le stockage a retrouvé ses performances"
require_cmd jq curl ssh

check_cmd "Ceph : aucun drapeau qui suspend la reconstruction ou les E/S (noout, norecover…)" _f3d_ceph_drapeaux_ok
check_cmd "Ceph : tous les OSD sont up et in" _f3d_ceph_osds_ok
_f3d_s08_l="$(_f3d_ceph_latence_max)"
if [[ "$_f3d_s08_l" =~ ^[0-9]+$ ]] && ((_f3d_s08_l < 100)); then
  _ok "Ceph : latence de commit maximale des OSD ${_f3d_s08_l} ms (< 100 ms)"
else
  _ko "Ceph : latence de commit d'un OSD à ${_f3d_s08_l:-?} ms"
fi
check_cmd "Ceph : le quota du pool ${WB_F3_S08_POOL:-k8s-rbd} laisse de la marge (aucun, ou ≥ 1,5 × le stocké)" _f3d_ceph_quota_ok
read -r -a _f3d_s08_vms <<<"${WB_F3_S08_CEPH_VMS:-ceph01:2081 ceph02:2082 ceph03:2083}"
for _f3d_s08_p in "${_f3d_s08_vms[@]}"; do
  check_cmd "${_f3d_s08_p%%:*} : aucune limite d'E/S sur ses disques (Proxmox)" _f3d_vm_sans_limite_es "${_f3d_s08_p#*:}"
done

check_cmd "RB-334 publié (docs/exploitation/runbooks/)" _f3d_rb_present RB-334
_f3s_sante
_f3s_trace INC-5908 2
