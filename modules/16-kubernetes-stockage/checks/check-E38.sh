# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes (variables jq, pas shell)
# shellcheck source-path=SCRIPTDIR
# check-E38.sh — M16-E38 « Panne : Ceph refuse de créer les volumes » : droits de client.k8s sur
# k8s-rbd (mon, osd, mgr), pool k8s-rbd ni plein ni au quota, volume de test lié si présent,
# témoins disponibles. Lecture seule (ceph auth get : seuls les droits sont lus, jamais la clé).

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E38 — Ceph crée les volumes de Kubernetes"
require_cmd kubectl jq ssh

_m16_e38_caps="$(_m16x_caps_k8s)"
if [[ -n "$_m16_e38_caps" ]]; then
  check_cmd "client.k8s : droits moniteurs « profile rbd »" _m16x_q "$_m16_e38_caps" '(.mon // "") | contains("profile rbd")'
  check_cmd "client.k8s : droits OSD « profile rbd pool=k8s-rbd »" _m16x_q "$_m16_e38_caps" '(.osd // "") | contains("profile rbd pool=k8s-rbd")'
  check_cmd "client.k8s : droits mgr « profile rbd pool=k8s-rbd »" _m16x_q "$_m16_e38_caps" '(.mgr // "") | contains("profile rbd pool=k8s-rbd")'
  check_cmd "client.k8s : aucun droit « allow * »" _m16x_q "$_m16_e38_caps" '[.[]] | all(.[]; contains("allow *") | not)'
  check_cmd "pool k8s-rbd : ni plein ni presque plein, quota absent ou avec 20 % de marge" _m16x_pool_sain
else
  skip "droits de client.k8s et état du pool" "ceph-par1 ne répond pas depuis $_m16x_admin (ou client.k8s absent)"
fi
_m16_e38_pvc="$(_m16x_j pvc temoin-e38 -n "$_m16x_ns_t")"
if [[ -n "$_m16_e38_pvc" ]]; then
  check_cmd "volume de test temoin-e38 lié (Bound)" _m16x_q "$_m16_e38_pvc" '.status.phase == "Bound"'
  check_cmd "pod de test temoin-e38 démarré" _m16x_q "$(_m16x_j pod temoin-e38 -n "$_m16x_ns_t")" '.status.phase == "Running"'
else
  skip "volume de test temoin-e38" "absent (panne non injectée ou déjà close)"
fi
check_cmd "témoins du palier 4 (volumes déjà montés) disponibles" _m16x_temoins_prets
check_cmd "panne M16-E38 close (lab/bin/break 16 38 --annuler après réparation)" _m16x_aucune_panne_active E38
