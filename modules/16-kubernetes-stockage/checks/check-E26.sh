# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E26.sh — M16-E26 « Chiffrer les volumes »
# Lecture seule : StorageClasses, ConfigMaps de l'espace ceph-csi (configuration des KMS, pas de
# Secrets), PV de la classe chiffrée, VolumeAttachment, lsblk sur le nœud, métadonnées des images
# RBD (rbd image-meta list sur l'hôte _admin), documentation (API GitLab).

# shellcheck source=_m16-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-production.sh"

title "M16-E26 — Chiffrer les volumes"
require_cmd jq kubectl curl

_m16_e26_sc="$(_m16p_kj storageclasses)"
title "Classes"
check_cmd "ceph-rbd-chiffre existe (rbd.csi.ceph.com, encrypted \"true\")" \
  _m16p_jq "$_m16_e26_sc" 'any(.items[]; .metadata.name == "ceph-rbd-chiffre" and .provisioner == "rbd.csi.ceph.com" and .parameters.encrypted == "true")'
check_cmd "ceph-rbd-chiffre : KMS secrets-metadata" \
  _m16p_jq "$_m16_e26_sc" 'any(.items[]; .metadata.name == "ceph-rbd-chiffre" and .parameters.encryptionKMSID == "secrets-metadata")'
check_cmd "ceph-rbd-chiffre : Secret du nœud distinct de celui de ceph-rbd" \
  _m16p_jq "$_m16_e26_sc" '([.items[] | select(.metadata.name == "ceph-rbd-chiffre") | .parameters["csi.storage.k8s.io/node-stage-secret-name"]][0]) as $c
    | ([.items[] | select(.metadata.name == "ceph-rbd") | .parameters["csi.storage.k8s.io/node-stage-secret-name"]][0]) as $r
    | ($c // "") != "" and $c != $r'
check_cmd "ceph-rbd reste la classe par défaut, sans chiffrement" \
  _m16p_jq "$_m16_e26_sc" 'any(.items[]; .metadata.name == "ceph-rbd"
    and .metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true" and ((.parameters.encrypted // "false") != "true"))'
check_cmd "ceph-rbd-chiffre n'est pas classe par défaut" \
  _m16p_jq "$_m16_e26_sc" 'any(.items[]; .metadata.name == "ceph-rbd-chiffre" and ((.metadata.annotations["storageclass.kubernetes.io/is-default-class"] // "false") != "true"))'
check_cmd "fournisseur secrets-metadata (type metadata) dans la ConfigMap de KMS de ceph-csi" \
  _m16p_jq "$(_m16p_kj configmaps -n ceph-csi)" 'any(.items[]; (.data["config.json"] // "{}") | (try fromjson catch {}) | .["secrets-metadata"].encryptionKMSType == "metadata")'

title "Transit (msgr2 secure) pour toutes les classes Ceph"
for _m16_e26_c in ceph-rbd ceph-rbd-retain ceph-rbd-chiffre; do
  check_cmd "$_m16_e26_c : mapOptions avec ms_mode=secure" \
    _m16p_jq "$_m16_e26_sc" "any(.items[]; .metadata.name == \"$_m16_e26_c\" and ((.parameters.mapOptions // \"\") | test(\"ms_mode=secure\")))"
done
check_cmd "cephfs : kernelMountOptions avec ms_mode=secure" \
  _m16p_jq "$_m16_e26_sc" 'any(.items[]; .metadata.name == "cephfs" and ((.parameters.kernelMountOptions // "") | test("ms_mode=secure")))'

title "Volume chiffré : sur le nœud et dans Ceph"
_m16_e26_pv="$(_m16p_kj pv | jq -r '[.items[]? | select(.spec.storageClassName == "ceph-rbd-chiffre" and .status.phase == "Bound") | .metadata.name][0] // empty')"
if [[ -z "$_m16_e26_pv" ]]; then
  check_cmd "au moins un volume lié de ceph-rbd-chiffre (e26-temoin, ou Valkey après E29)" false
else
  check_cmd "un volume de ceph-rbd-chiffre est lié ($_m16_e26_pv)" true
  _m16_e26_img="$(_m16p_image_pv "$_m16_e26_pv")" || _m16_e26_img=""
  check_cmd "image $_m16_e26_img : état « encrypted » et DEK enveloppée dans ses métadonnées" \
    _m16p_image_chiffree "$_m16_e26_img"
  _m16_e26_noeud="$(_m16p_noeud_pv "$_m16_e26_pv")" || _m16_e26_noeud=""
  if [[ -n "$_m16_e26_noeud" ]]; then
    check_cmd "$_m16_e26_noeud : un périphérique dm-crypt est ouvert (LUKS)" _m16p_crypt_sur "$_m16_e26_noeud"
  else
    check_cmd "le volume chiffré est attaché à un nœud (pod qui le monte)" false
  fi
fi
check_cmd "le volume de contrôle e26-clair a été supprimé" \
  _m16p_jq "$(_m16p_kj pvc -n wb-essais)" 'all(.items[]?; .metadata.name != "e26-clair")'

title "Documentation"
check_cmd "chiffrement.md sur main (modèle de menace, KEK, détenteurs)" \
  _m16p_doc_main docs/kubernetes/stockage/chiffrement.md 'KEK' 'DEK' 'menace' 'ms_mode|msgr2'
