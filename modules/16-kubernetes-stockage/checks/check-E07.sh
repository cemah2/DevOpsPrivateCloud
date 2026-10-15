# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E07.sh — M16-E07 : ceph-csi, des volumes partagés CephFS
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks), commandes « ceph »
# d'observation sur le nœud _admin, API GitLab en GET.

# shellcheck source=_m16-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-decouverte.sh"

title "M16-E07 — ceph-csi : des volumes partagés CephFS"
require_cmd jq kubectl curl

_m16d_e07_fsid="$(_m16d_fsid)"
_m16d_e07_gio=$((20 * 1024 * 1024 * 1024))

# --- 1. Côté Ceph -----------------------------------------------------------------------------------------
check_cmd "client.k8s-cephfs : exactement les droits de la documentation ceph-csi (fsname cephfs, groupe csi)" \
  _m16d_json "$(_m16d_ceph "auth get client.k8s-cephfs -f json")" '
    .[0].caps == {
      "mds": "allow r fsname=cephfs path=/volumes, allow rws fsname=cephfs path=/volumes/csi",
      "mgr": "allow rw",
      "mon": "allow r fsname=cephfs",
      "osd": "allow rwx tag cephfs metadata=cephfs, allow rw tag cephfs data=cephfs"}'
check_cmd "groupe de sous-volumes cephfs/csi présent, plafond 20 Gio" \
  _m16d_json "$(_m16d_ceph "fs subvolumegroup info cephfs csi -f json")" '.bytes_quota == $q' --argjson q "$_m16d_e07_gio"
_m16d_e07_alloc="$(_m16d_contenu_main plateforme/ceph allocations.yaml)"
check_cmd "plateforme/ceph (main) : allocations.yaml décrit client.k8s-cephfs et le groupe csi" \
  bash -c 'grep -q "client.k8s-cephfs" <<<"$1" && grep -Eq "nom: *csi" <<<"$1"' _ "$_m16d_e07_alloc"
check_cmd "plateforme/ceph (main) : ceph-allocations.sh gère les groupes de sous-volumes de consommateurs" \
  bash -c 'grep -q "\.groupes" <<<"$1"' _ "$(_m16d_contenu_main plateforme/ceph outils/ceph-allocations.sh)"

# --- 2. Le pilote CephFS --------------------------------------------------------------------------------
check_cmd "nodeplugin CephFS : image cephcsi $_M16D_CSI_VERSION, tous les pods prêts" \
  _m16d_json "$(_m16d_kj get daemonset ceph-csi-cephfs-nodeplugin -n ceph-csi)" '
    any(.spec.template.spec.containers[]; .name == "csi-cephfsplugin" and (.image | endswith("cephcsi:" + $v)))
    and .status.desiredNumberScheduled > 0 and .status.numberReady == .status.desiredNumberScheduled' \
  --arg v "$_M16D_CSI_VERSION"
check_cmd "nodeplugin CephFS : exactement sur les travailleurs" \
  bash -c 'diff <(printf "%s\n" "$1") <(printf "%s\n" "$2") >/dev/null' _ \
  "$(_m16d_noeuds_pods ceph-csi app=ceph-csi-cephfs,component=nodeplugin)" "$(_m16d_travailleurs_tries)"
check_cmd "provisioner CephFS : 2 réplicas prêts" \
  _m16d_json "$(_m16d_kj get deployment ceph-csi-cephfs-provisioner -n ceph-csi)" \
  '.spec.replicas == 2 and (.status.readyReplicas // 0) == 2'
check_cmd "CSIDriver cephfs.csi.ceph.com présent" \
  _m16d_json "$(_m16d_kj get csidriver cephfs.csi.ceph.com)" '.metadata.name == "cephfs.csi.ceph.com"'
_m16d_e07_conf="$(_m16d_kj get configmap ceph-csi-config-cephfs -n ceph-csi | jq -r '.data["config.json"] // empty' 2>/dev/null || true)"
check_cmd "configuration CephFS (ceph-csi-config-cephfs) : même cluster, moniteurs en 3300, groupe csi" \
  _m16d_json "$_m16d_e07_conf" '
    length == 1 and .[0].clusterID == $f and .[0].cephFS.subvolumeGroup == "csi"
    and (.[0].monitors | sort) == ["10.10.30.51:3300", "10.10.30.52:3300", "10.10.30.53:3300"]' \
  --arg f "$_m16d_e07_fsid"
check_cmd "pas de collision de noms : ceph-csi-config appartient toujours à la release RBD" \
  _m16d_json "$(_m16d_kj get configmap ceph-csi-config -n ceph-csi)" \
  '.metadata.annotations["meta.helm.sh/release-name"] == "ceph-csi-rbd"'

# --- 3. La classe ---------------------------------------------------------------------------------------
check_cmd "classe cephfs : cephfs.csi.ceph.com, fsName cephfs, client noyau, ms_mode=secure, Delete, non par défaut" \
  _m16d_json "$(_m16d_sc cephfs)" '
    .provisioner == "cephfs.csi.ceph.com" and .parameters.clusterID == $f and .parameters.fsName == "cephfs"
    and .parameters.mounter == "kernel" and (.parameters.kernelMountOptions // "" | test("ms_mode=secure"))
    and .parameters["csi.storage.k8s.io/node-stage-secret-name"] == "csi-cephfs-secret"
    and .parameters["csi.storage.k8s.io/provisioner-secret-name"] == "csi-cephfs-secret"
    and .reclaimPolicy == "Delete" and .allowVolumeExpansion == true
    and (.metadata.annotations["storageclass.kubernetes.io/is-default-class"] // "false") != "true"' \
  --arg f "$_m16d_e07_fsid"

# --- 4. Le volume partagé -------------------------------------------------------------------------------
check_cmd "PVC wb-essais/e07-partage lié en ReadWriteMany dans cephfs" \
  _m16d_json "$(_m16d_kj get pvc e07-partage -n wb-essais)" \
  '.status.phase == "Bound" and .spec.storageClassName == "cephfs" and (.status.accessModes | index("ReadWriteMany"))'
check_cmd "e07-ecrivains : 2 pods prêts" \
  bash -c '[[ "$1" == 2 ]]' _ "$(_m16d_pods_prets wb-essais app.kubernetes.io/name=e07-ecrivains)"
check_cmd "e07-ecrivains : sur deux nœuds différents" \
  bash -c '[[ "$(grep -c . <<<"$1")" == 2 ]]' _ "$(_m16d_noeuds_pods wb-essais app.kubernetes.io/name=e07-ecrivains)"
check_cmd "au moins un sous-volume dans le groupe csi" \
  _m16d_json "$(_m16d_ceph "fs subvolume ls cephfs --group_name csi -f json")" 'length >= 1'
check_cmd "plus de PVC e07-rbd-rwx" _m16d_absent pvc e07-rbd-rwx -n wb-essais

# --- 5. Le code -----------------------------------------------------------------------------------------
for _m16d_e07_f in composants/ceph-csi/values-cephfs.yaml composants/ceph-csi/classes/cephfs.yaml; do
  check_cmd "plateforme/k8s (main) : $_m16d_e07_f" _m16d_fichier_main plateforme/k8s "$_m16d_e07_f"
done
