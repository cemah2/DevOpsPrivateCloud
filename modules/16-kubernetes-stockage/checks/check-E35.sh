# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas shell)
# shellcheck source-path=SCRIPTDIR
# check-E35.sh — M16-E35 « Panne : le PVC reste Pending » : une seule classe par défaut (ceph-rbd),
# provisioner RBD disponible, aucun quota de stockage saturé dans wb-essais, application de test
# temoin-e35 démarrée si elle existe encore. Lecture seule.

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E35 — Les PVC se lient"
require_cmd kubectl jq

_m16_e35_sc="$(_m16x_j storageclass)"
check_cmd "exactement une classe par défaut, et c'est ceph-rbd" _m16x_q "$_m16_e35_sc" \
  '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | .metadata.name] == ["ceph-rbd"]'
check_cmd "provisioner RBD (ceph-csi-rbd-provisioner) : toutes ses répliques disponibles" \
  _m16x_deploiement_pret "$_m16x_ns_csi" ceph-csi-rbd-provisioner
check_cmd "wb-essais : aucun quota de stockage atteint (nombre de PVC ou capacité par classe)" _m16x_q \
  "$(_m16x_j resourcequota -n "$_m16x_ns_t")" \
  'all(.items[]; . as $q | all(($q.status.hard // {}) | to_entries[]
     | select(.key | test("persistentvolumeclaims$|requests.storage$")); ($q.status.used[.key] // "0") != .value))'

_m16_e35_sts="$(_m16x_j statefulset temoin-e35 -n "$_m16x_ns_t")"
if [[ -n "$_m16_e35_sts" ]]; then
  check_cmd "temoin-e35 : 1 réplique prête" _m16x_q "$_m16_e35_sts" '.status.readyReplicas == 1'
  _m16_e35_pvc="$(_m16x_j pvc donnees-temoin-e35-0 -n "$_m16x_ns_t")"
  check_cmd "temoin-e35 : volume donnees-temoin-e35-0 lié (Bound) sur une classe existante" bash -c \
    'jq -e ".status.phase == \"Bound\"" >/dev/null <<<"$1" && jq -e --arg c "$(jq -r .spec.storageClassName <<<"$1")" "any(.items[]; .metadata.name == \$c)" >/dev/null <<<"$2"' \
    _ "$_m16_e35_pvc" "$_m16_e35_sc"
else
  skip "application de test temoin-e35" "absente (panne non injectée ou déjà close)"
fi
check_cmd "témoins du palier 4 (temoin-rbd, temoin-cephfs) disponibles" _m16x_temoins_prets
check_cmd "panne M16-E35 close (lab/bin/break 16 35 --annuler après réparation)" _m16x_aucune_panne_active E35
