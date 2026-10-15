# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas shell)
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M16-E36 « Panne : le pod reste en ContainerCreating » : pilote RBD présent et
# enregistré sur chaque travailleur, moniteurs de ceph-par1 joignables depuis chaque travailleur,
# application de test temoin-e36 démarrée sur son nœud si elle existe encore. Lecture seule.

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E36 — Les volumes se montent sur tous les travailleurs"
require_cmd kubectl jq ssh

check_cmd "nodeplugin RBD (ceph-csi-rbd-nodeplugin) prêt sur chaque travailleur" \
  _m16x_ds_complet "$_m16x_ns_csi" ceph-csi-rbd-nodeplugin
_m16_e36_csinodes="$(_m16x_j csinodes)"
for _m16_e36_n in "${_m16x_travailleurs[@]}"; do
  check_cmd "$_m16_e36_n : pilote rbd.csi.ceph.com enregistré (CSINode)" _m16x_q "$_m16_e36_csinodes" \
    'any(.items[]; .metadata.name == $n and any(.spec.drivers[]?; .name == "rbd.csi.ceph.com"))' --arg n "$_m16_e36_n"
  check_ssh "$_m16_e36_n : moniteurs de ceph-par1 joignables (10.10.30.51-53, port 3300)" "$_m16_e36_n" \
    "for m in 10.10.30.51 10.10.30.52 10.10.30.53; do timeout 3 bash -c \"</dev/tcp/\$m/3300\" || exit 1; done"
done

_m16_e36_dep="$(_m16x_j deployment temoin-e36 -n "$_m16x_ns_t")"
if [[ -n "$_m16_e36_dep" ]]; then
  _m16_e36_noeud="$(jq -r '.spec.template.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0] // empty' <<<"$_m16_e36_dep")"
  check_cmd "temoin-e36 : pod démarré et prêt sur ${_m16_e36_noeud:-son nœud}" _m16x_q \
    "$(_m16x_j pods -n "$_m16x_ns_t" -l app.kubernetes.io/name=temoin-e36)" \
    'any(.items[]; .spec.nodeName == $n and .status.phase == "Running" and all(.status.containerStatuses[]?; .ready))' \
    --arg n "$_m16_e36_noeud"
else
  skip "application de test temoin-e36" "absente (panne non injectée ou déjà close)"
fi
check_cmd "témoins du palier 4 (temoin-rbd, temoin-cephfs) disponibles" _m16x_temoins_prets
check_cmd "panne M16-E36 close (lab/bin/break 16 36 --annuler après réparation)" _m16x_aucune_panne_active E36
