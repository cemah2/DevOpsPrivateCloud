# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas shell)
# shellcheck source-path=SCRIPTDIR
# check-E42.sh — M16-E42 « Panne : le snapshot ne se termine jamais » : contrôleur de snapshots
# disponible et lié à ses droits, VolumeSnapshotClass ceph-rbd-snap cohérente avec la StorageClass
# ceph-rbd, aucun instantané bloqué dans wb-essais, un instantané prêt depuis l'incident.

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E42 — Les instantanés se terminent"
require_cmd kubectl jq

check_cmd "snapshot-controller (kube-system) disponible" _m16x_deploiement_pret kube-system snapshot-controller
check_cmd "snapshot-controller : son compte de service est lié à un ClusterRole" _m16x_q "$(_m16x_j clusterrolebindings)" \
  'any(.items[]; any(.subjects[]?; .kind == "ServiceAccount" and .name == "snapshot-controller" and .namespace == "kube-system"))'
_m16_e42_sc="$(_m16x_j storageclass "$_m16x_sc_rbd")"
_m16_e42_vsc="$(_m16x_j volumesnapshotclass "$_m16x_vsc_rbd")"
check_cmd "ceph-rbd-snap : pilote rbd.csi.ceph.com, même clusterID que ceph-rbd" bash -c \
  'jq -e --arg c "$(jq -r .parameters.clusterID <<<"$2")" ".driver == \"rbd.csi.ceph.com\" and .parameters.clusterID == \$c" >/dev/null <<<"$1"' \
  _ "$_m16_e42_vsc" "$_m16_e42_sc"
check_cmd "ceph-rbd-snap : Secret du snapshotter dans l'espace des Secrets de ceph-rbd" bash -c \
  'jq -e --arg n "$(jq -r ".parameters[\"csi.storage.k8s.io/provisioner-secret-namespace\"]" <<<"$2")" ".parameters[\"csi.storage.k8s.io/snapshotter-secret-namespace\"] == \$n" >/dev/null <<<"$1"' \
  _ "$_m16_e42_vsc" "$_m16_e42_sc"
_m16_e42_vs="$(_m16x_j volumesnapshots -n "$_m16x_ns_t")"
check_cmd "wb-essais : aucun instantané non prêt depuis plus de 10 min" _m16x_q "$_m16_e42_vs" \
  'all(.items[]; (.status.readyToUse == true) or ((.metadata.creationTimestamp | fromdateiso8601) > (now - 600)))'
check_cmd "wb-essais : un instantané prêt (readyToUse) demandé depuis l'incident" _m16x_cree_apres \
  "$_m16_e42_vs" "$(_m16x_injection E42)" '.status.readyToUse == true'
check_cmd "panne M16-E42 close (lab/bin/break 16 42 --annuler après réparation)" _m16x_aucune_panne_active E42
