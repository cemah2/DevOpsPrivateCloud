# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E44.sh — M16-E44 « Sous le capot : du PVC au bloc monté » : la note d'exploration est
# publiée et suit un volume réel à chaque étage, et l'outil k8s-suivre-volume.sh est livré dans
# plateforme/outils (branche main). Lecture seule.

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E44 — Du PVC au bloc monté"
require_cmd jq curl

_m16_e44_doc=docs/kubernetes/stockage/du-pvc-au-bloc.md
check_cmd "note $_m16_e44_doc publiée (branche main)" _m16x_doc_main "$_m16_e44_doc" '.'
check_cmd "note : PV et image RBD réels (csi-vol-…, pool k8s-rbd)" _m16x_doc_main "$_m16_e44_doc" 'csi-vol-[0-9a-f]{8}' 'k8s-rbd'
check_cmd "note : appels CSI suivis (CreateVolume, ControllerPublishVolume, NodeStageVolume, NodePublishVolume)" \
  _m16x_doc_main "$_m16_e44_doc" 'CreateVolume' 'ControllerPublishVolume' 'NodeStageVolume' 'NodePublishVolume'
check_cmd "note : VolumeAttachment, périphérique /dev/rbdN, montage global et montage du pod" \
  _m16x_doc_main "$_m16_e44_doc" 'VolumeAttachment' '/dev/rbd[0-9]' 'globalmount' '/var/lib/kubelet/pods/'
check_cmd "note : côté Ceph (watchers de l'image, correspondance omap de ceph-csi)" \
  _m16x_doc_main "$_m16_e44_doc" 'watcher' 'omap|csi\.volume'
check_cmd "note : volume CephFS suivi (sous-volume du groupe csi, montage ceph)" \
  _m16x_doc_main "$_m16_e44_doc" 'subvolume|sous-volume' 'csi'
_m16_e44_outil() { _m16x_arbre plateforme/outils "" | grep -q 'k8s-suivre-volume\.sh$'; }
check_cmd "outil k8s-suivre-volume.sh livré dans plateforme/outils" _m16_e44_outil
