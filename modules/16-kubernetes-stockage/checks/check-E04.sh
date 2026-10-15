# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E04.sh — M16-E04 : comprendre CSI (à lancer après M16-E06)
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks), API GitLab en GET.

# shellcheck source=_m16-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-decouverte.sh"

title "M16-E04 — Comprendre CSI"
require_cmd jq kubectl curl

# --- 1. Le pilote déclaré ------------------------------------------------------------------------------
check_cmd "CSIDriver rbd.csi.ceph.com présent, avec attachement (attachRequired)" \
  _m16d_json "$(_m16d_kj get csidriver rbd.csi.ceph.com)" '.spec.attachRequired == true'

_m16d_e04_csinodes="$(_m16d_kj get csinodes)"
for _m16d_e04_n in $_M16D_TRAVAILLEURS; do
  check_cmd "CSINode $_m16d_e04_n : le pilote rbd.csi.ceph.com est inscrit" _m16d_json "$_m16d_e04_csinodes" \
    '.items[] | select(.metadata.name == $n) | any(.spec.drivers[]?; .name == "rbd.csi.ceph.com")' --arg n "$_m16d_e04_n"
done
for _m16d_e04_n in $_M16D_CP; do
  check_cmd "CSINode $_m16d_e04_n (contrôle) : aucun pilote ceph-csi" _m16d_json "$_m16d_e04_csinodes" \
    '[.items[] | select(.metadata.name == $n)] | length == 1 and all(.[]; all(.spec.drivers[]?; .name | test("ceph.com$") | not))' \
    --arg n "$_m16d_e04_n"
done

# --- 2. L'attachement du volume de E06 ------------------------------------------------------------------
_m16d_e04_pvc="$(_m16d_kj get pvc e06-essai -n wb-essais)"
_m16d_e04_pod="$(_m16d_kj get pod e06-essai -n wb-essais)"
_m16d_e04_pv="$(jq -r '.spec.volumeName // empty' <<<"$_m16d_e04_pvc" 2>/dev/null || true)"
_m16d_e04_noeud="$(jq -r '.spec.nodeName // empty' <<<"$_m16d_e04_pod" 2>/dev/null || true)"
check_cmd "le pod wb-essais/e06-essai tourne et son PVC est lié" \
  bash -c '[[ -n "$1" && -n "$2" ]]' _ "$_m16d_e04_pv" "$_m16d_e04_noeud"
check_cmd "un VolumeAttachment attaché relie le PV de e06-essai (${_m16d_e04_pv:-?}) au nœud du pod (${_m16d_e04_noeud:-?})" \
  _m16d_json "$(_m16d_kj get volumeattachments)" '
    [.items[] | select(.spec.attacher == "rbd.csi.ceph.com" and .spec.source.persistentVolumeName == $pv
                       and .spec.nodeName == $n and .status.attached == true)] | length == 1' \
  --arg pv "$_m16d_e04_pv" --arg n "$_m16d_e04_noeud"

# --- 3. Ménage ----------------------------------------------------------------------------------------
check_cmd "plus de PVC e04-jetable dans wb-essais" _m16d_absent pvc e04-jetable -n wb-essais

# --- 4. La fiche ---------------------------------------------------------------------------------------
_m16d_e04_doc="$(_m16d_contenu_main plateforme/medisphere docs/kubernetes/stockage/csi.md)"
for _m16d_e04_mot in CreateVolume ControllerPublishVolume NodeStageVolume NodePublishVolume VolumeAttachment; do
  check_cmd "plateforme/medisphere (main) : docs/kubernetes/stockage/csi.md nomme $_m16d_e04_mot" \
    grep -q -- "$_m16d_e04_mot" <<<"$_m16d_e04_doc"
done
