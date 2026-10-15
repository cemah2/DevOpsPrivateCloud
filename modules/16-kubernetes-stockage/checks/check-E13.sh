# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E13.sh — M16-E13 : Rook : un Ceph dans le cluster
# À lancer depuis adm01. Lecture seule : objets Kubernetes (wb-checks, jamais les Secrets), disques des travailleurs (SSH, lsblk), journal local.

# shellcheck source=_m16-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-operationnel.sh"

title "M16-E13 — Rook : un Ceph dans le cluster"
# À lancer AVANT le démontage d'E14 (après, ce check est rouge par construction).
require_cmd jq kubectl ssh

check_cmd "l'API du cluster répond au compte des vérifications" _m16o_api_repond
check_cmd "espace rook-ceph en Pod Security « privileged »" _m16o_json "$(_m16o_kj get namespace rook-ceph)" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] == "privileged"'
check_cmd "opérateur rook-ceph-operator disponible, Rook v1.21.0" \
  _m16o_json "$(_m16o_kj get deployment rook-ceph-operator -n rook-ceph)" \
  '(.status.availableReplicas // 0) >= 1 and any(.spec.template.spec.containers[]; .image | test(":v1\\.21\\.0$"))'
_m16o_cc="$(_m16o_kj get cephclusters.ceph.rook.io rook-ceph -n rook-ceph)"
check_cmd "CephCluster rook-ceph prêt (phase Ready, santé HEALTH_OK ou HEALTH_WARN)" _m16o_json "$_m16o_cc" \
  '.status.phase == "Ready" and (.status.ceph.health // "") as $h | ($h == "HEALTH_OK" or $h == "HEALTH_WARN")'
check_cmd "CephCluster : 3 MON, msgr2 exigé, disques désignés (ni useAllNodes ni useAllDevices)" _m16o_json "$_m16o_cc" '
  .spec.mon.count == 3 and .spec.network.connections.requireMsgr2 == true
  and (.spec.storage.useAllNodes // true) == false and (.spec.storage.useAllDevices // true) == false
  and ([.spec.storage.nodes[]?.devices[]?.name] | length >= 3 and all(test("-rook$")))'
_m16o_pods="$(_m16o_kj get pods -n rook-ceph)"
check_cmd "3 MON en marche" _m16o_json "$_m16o_pods" \
  '[.items[] | select(.metadata.labels.app == "rook-ceph-mon" and .status.phase == "Running")] | length == 3'
check_cmd "au moins 1 MGR en marche" _m16o_json "$_m16o_pods" \
  '[.items[] | select(.metadata.labels.app == "rook-ceph-mgr" and .status.phase == "Running")] | length >= 1'
check_cmd "3 OSD en marche, sur trois travailleurs différents" _m16o_json "$_m16o_pods" '
  [.items[] | select(.metadata.labels.app == "rook-ceph-osd" and .status.phase == "Running") | .spec.nodeName]
  | length == 3 and (unique | length) == 3'
check_cmd "pool rook-essai prêt" _m16o_json "$(_m16o_kj get cephblockpools.ceph.rook.io rook-essai -n rook-ceph)" \
  '.status.phase == "Ready"'
check_cmd "classe rook-ceph-block (pilote de Rook), pas par défaut" _m16o_json "$(_m16o_kj get storageclass rook-ceph-block)" \
  '.provisioner == "rook-ceph.rbd.csi.ceph.com" and (.metadata.annotations["storageclass.kubernetes.io/is-default-class"] // "false") != "true"'
check_cmd "ceph-rbd reste la seule classe par défaut" _m16o_defaut_unique
_m16o_pv="$(_m16o_kj get pvc rook-essai -n wb-essais | jq -r '.spec.volumeName // empty' 2>/dev/null || true)"
check_cmd "PVC wb-essais/rook-essai lié par le pilote de Rook" bash -c '[[ -n "$1" ]]' _ "$_m16o_pv"
if [[ -n "$_m16o_pv" ]]; then
  check_cmd "son PV vient de rook-ceph.rbd.csi.ceph.com" _m16o_json "$(_m16o_kj get pv "$_m16o_pv")" \
    '.spec.csi.driver == "rook-ceph.rbd.csi.ceph.com"'
fi
check_cmd "disque <nœud>-rook de 32 Gio sur chaque travailleur" _m16o_disque_32g rook
check_cmd "journal ~/m16/e13/journal.md avec l'empreinte mesurée (mémoire)" \
  _m16o_journal_tout E13 10 '(mémoire|memoire|[0-9] ?(Mi|Gi|Go|Mo))'
