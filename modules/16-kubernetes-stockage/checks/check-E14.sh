# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E14.sh — M16-E14 : Rook : exploiter puis démonter proprement
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets), nœuds en SSH (wipefs -n, ls), journal local.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E14 — Rook : exploiter puis démonter proprement"
require_cmd jq kubectl ssh

check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
check_cmd "l'espace rook-ceph n'existe plus" _m16o_absent namespace rook-ceph
check_cmd "aucune CRD *.ceph.rook.io ni *.csi.ceph.io ne reste" _m16o_json "$(_m16o_kj get crd)" \
  '[.items[] | select(.metadata.name | test("\\.(ceph\\.rook|csi\\.ceph)\\.io$"))] | length == 0'
check_cmd "aucun CSIDriver de Rook (rook-ceph.*)" _m16o_json "$(_m16o_kj get csidrivers)" \
  '[.items[] | select(.metadata.name | startswith("rook-ceph."))] | length == 0'
check_cmd "aucune StorageClass ni aucun PV du pilote de Rook" bash -c '
  jq -e "[.items[] | select(.provisioner | startswith(\"rook-ceph.\"))] | length == 0" <<<"$1" >/dev/null &&
  jq -e "[.items[] | select((.spec.csi.driver // \"\") | startswith(\"rook-ceph.\"))] | length == 0" <<<"$2" >/dev/null' \
  _ "$(_m16o_kj get storageclass)" "$(_m16o_kj get pv)"
check_cmd "les pilotes d'E06 sont toujours là (rbd.csi.ceph.com, cephfs.csi.ceph.com)" _m16o_json "$(_m16o_kj get csidrivers)" \
  '[.items[].metadata.name] | index("rbd.csi.ceph.com") != null and index("cephfs.csi.ceph.com") != null'
check_cmd "les CRD d'instantanés sont toujours là" _m16o_json "$(_m16o_kj get crd volumesnapshots.snapshot.storage.k8s.io)" '.metadata.name != null'
check_cmd "ceph-rbd reste la seule classe par défaut" _m16o_defaut_unique
check_cmd "travailleurs : /var/lib/rook n'existe plus" _m16o_sur_travailleurs 'test ! -e /var/lib/rook'
check_cmd "travailleurs : disque <nœud>-rook présent (32 Gio)" _m16o_disque_32g rook
check_cmd "travailleurs : disque <nœud>-rook sans aucune signature" _m16o_disque_vierge rook
check_cmd "travailleurs : aucune carte device-mapper ceph-*" _m16o_sur_travailleurs '! ls /dev/mapper/ 2>/dev/null | grep -q "^ceph-"'
check_cmd "journal : panne d'OSD observée (états et heures)" _m16o_journal_tout E14 5 \
  'osd' '(degraded|undersized|down)' '[0-2]?[0-9][:h][0-5][0-9]'
check_cmd "journal : séquence de démontage écrite (cleanupPolicy)" _m16o_journal_mentionne E14 "cleanupPolicy"
