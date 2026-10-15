# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas shell)
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M16-E37 « Panne : le volume est déjà attaché ailleurs » : tous les nœuds Ready et
# kubelet actif, aucune teinte de mise hors service restée, le témoin temoin-rbd tourne avec un seul
# pod et son volume n'est attaché qu'à un nœud, le sien. Lecture seule.

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E37 — Un volume RWO, un seul nœud"
require_cmd kubectl jq ssh

check_cmd "tous les nœuds sont Ready" _m16x_noeuds_prets
for _m16_e37_n in "${_m16x_travailleurs[@]}"; do
  check_ssh "$_m16_e37_n : kubelet actif" "$_m16_e37_n" "systemctl is-active --quiet kubelet"
done
check_cmd "aucun nœud ne garde la teinte node.kubernetes.io/out-of-service" _m16x_q "$(_m16x_j nodes)" \
  'all(.items[]; all(.spec.taints[]?; .key != "node.kubernetes.io/out-of-service"))'

_m16_e37_pods="$(_m16x_j pods -n "$_m16x_ns_t" -l app.kubernetes.io/name=temoin-rbd)"
check_cmd "temoin-rbd : un seul pod, prêt, aucun pod bloqué en Terminating" _m16x_q "$_m16_e37_pods" \
  '(.items | length) == 1 and (.items[0].metadata.deletionTimestamp == null)
   and all(.items[0].status.containerStatuses[]?; .ready)'
_m16_e37_noeud="$(jq -r '.items[0].spec.nodeName // empty' <<<"$_m16_e37_pods" 2>/dev/null)"
_m16_e37_pv="$(kube get pvc temoin-rbd -n "$_m16x_ns_t" -o jsonpath='{.spec.volumeName}' 2>/dev/null)"
check_cmd "volume de temoin-rbd attaché au seul nœud de son pod (${_m16_e37_noeud:-?})" _m16x_q \
  "$(_m16x_j volumeattachments)" \
  '[.items[] | select(.spec.source.persistentVolumeName == $pv)] as $va
   | ($va | length) == 1 and $va[0].spec.nodeName == $n and ($va[0].status.attached // false)' \
  --arg pv "${_m16_e37_pv:-?}" --arg n "${_m16_e37_noeud:-?}"
check_cmd "témoin temoin-cephfs disponible" _m16x_deploiement_pret "$_m16x_ns_t" temoin-cephfs
check_cmd "panne M16-E37 close (lab/bin/break 16 37 --annuler après réparation)" _m16x_aucune_panne_active E37
