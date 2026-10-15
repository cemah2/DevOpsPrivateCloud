# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E10.sh — M16-E10 : Snapshots et clones de volumes
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets), journal local.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E10 — Snapshots et clones de volumes"
require_cmd jq kubectl

check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
# --- Droits des vérifications ------------------------------------------------------------------------
check_cmd "wb-checks lit les instantanés de tout le cluster" kube get volumesnapshots.snapshot.storage.k8s.io -A
check_output "wb-checks ne peut PAS créer d'instantané" '^no' _m16o_peut create volumesnapshots.snapshot.storage.k8s.io wb-essais
check_output "wb-checks ne peut PAS lire les Secrets de ceph-csi" '^no' _m16o_peut get secrets ceph-csi

# --- Contrôleur (E06) et classes d'instantanés ---------------------------------------------------------
for _m16o_crd in volumesnapshots volumesnapshotcontents volumesnapshotclasses; do
  check_cmd "CRD $_m16o_crd.snapshot.storage.k8s.io servie en v1" \
    _m16o_json "$(_m16o_kj get crd "$_m16o_crd.snapshot.storage.k8s.io")" 'any(.spec.versions[]; .name == "v1" and .served)'
done
check_cmd "snapshot-controller disponible dans kube-system (v8.6.0)" \
  _m16o_json "$(_m16o_kj get deployment snapshot-controller -n kube-system)" \
  '(.status.availableReplicas // 0) >= 1 and any(.spec.template.spec.containers[]; .image | endswith(":v8.6.0"))'
_m16o_vsc="$(_m16o_kj get volumesnapshotclasses.snapshot.storage.k8s.io)"
for _m16o_c in ceph-rbd-snap:rbd.csi.ceph.com cephfs-snap:cephfs.csi.ceph.com; do
  check_cmd "classe ${_m16o_c%%:*} : pilote ${_m16o_c##*:}, Delete, par défaut, Secret de l'instantaneur" \
    _m16o_json "$_m16o_vsc" '.items[] | select(.metadata.name == $n)
      | .driver == $d and .deletionPolicy == "Delete"
        and .metadata.annotations["snapshot.storage.kubernetes.io/is-default-class"] == "true"
        and (.parameters["csi.storage.k8s.io/snapshotter-secret-name"] // "") != ""
        and (.parameters.clusterID // "") != ""' --arg n "${_m16o_c%%:*}" --arg d "${_m16o_c##*:}"
done
check_cmd "une seule classe d'instantanés par défaut pour chaque pilote" _m16o_json "$_m16o_vsc" '
  [.items[] | select(.metadata.annotations["snapshot.storage.kubernetes.io/is-default-class"] == "true") | .driver]
  | (length == (unique | length)) and length >= 2'

# --- Essais de wb-essais -------------------------------------------------------------------------------
_m16o_vs="$(_m16o_kj get volumesnapshots.snapshot.storage.k8s.io -n wb-essais)"
for _m16o_s in donnees-s1:donnees partage-s1:partage; do
  check_cmd "instantané ${_m16o_s%%:*} du PVC ${_m16o_s##*:} prêt (readyToUse)" _m16o_json "$_m16o_vs" '
    .items[] | select(.metadata.name == $n) | .spec.source.persistentVolumeClaimName == $p and .status.readyToUse == true' \
    --arg n "${_m16o_s%%:*}" --arg p "${_m16o_s##*:}"
done
_m16o_pvcs="$(_m16o_kj get pvc -n wb-essais)"
for _m16o_r in donnees-restauree:VolumeSnapshot:donnees-s1 partage-restauree:VolumeSnapshot:partage-s1 donnees-clone:PersistentVolumeClaim:donnees; do
  IFS=: read -r _m16o_n _m16o_k _m16o_src <<<"$_m16o_r"
  check_cmd "PVC $_m16o_n lié, créé depuis $_m16o_k $_m16o_src" _m16o_json "$_m16o_pvcs" '
    .items[] | select(.metadata.name == $n)
    | .status.phase == "Bound" and ((.spec.dataSource // .spec.dataSourceRef // {}) | .kind == $k and .name == $s)' \
    --arg n "$_m16o_n" --arg k "$_m16o_k" --arg s "$_m16o_src"
done
check_cmd "journal ~/m16/e10/journal.md rédigé" _m16o_journal E10 10
