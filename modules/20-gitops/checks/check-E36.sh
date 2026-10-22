# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M20-E36 « Panne : la synchronisation échoue » : dernière synchronisation de dev
# réussie, aucun refus d'AppProject, aucun hook en échec, sélecteur du Deployment inchangé, aucun
# Service LoadBalancer dans l'overlay de dev, RB-200 et journal, panne close. Lecture seule.

# shellcheck source=_m20-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-expert.sh"

title "M20-E36 — La synchronisation de dev réussit"
require_cmd jq kubectl curl

if ! _m20x_argo_lisible; then
  skip "Applications d'Argo CD" "le compte des checks ne lit pas les Applications (wb-checks-livraison, M20-E03)"
else
  check_cmd "$_m20x_app_dev : Synced, Healthy, dernière opération Succeeded" _m20x_app_saine "$_m20x_app_dev"
  check_cmd "$_m20x_app_dev : la dernière opération porte sur la révision courante" \
    _m20x_app_jq "$_m20x_app_dev" '(.status.operationState.syncResult.revision // "") == (.status.sync.revision // "x")'
  _m20_e36_aucun_refus() {
    kube -n "$_m20x_ns" get applications.argoproj.io -o json 2>/dev/null |
      jq -e '[.items[].status.conditions[]? | select((.message // "") | test("not permitted in project"))] | length == 0' >/dev/null 2>&1
  }
  check_cmd "aucune Application ne signale une ressource refusée par son AppProject" _m20_e36_aucun_refus
  check_cmd "mediagenda-dev : aucun Job de hook Argo CD en échec" \
    _m20x_kq '[.items[] | select(.metadata.annotations["argocd.argoproj.io/hook"] != null) | select((.status.failed // 0) > 0)] | length == 0' \
    -n "$_m20x_ns_dev" jobs
  check_cmd "mediagenda-dev : sélecteur du Deployment mediagenda limité aux étiquettes du chart" \
    _m20x_kq '(.spec.selector.matchLabels | keys) - ["app.kubernetes.io/name","app.kubernetes.io/instance","app.kubernetes.io/component"] | length == 0' \
    -n "$_m20x_ns_dev" deploy mediagenda
  check_cmd "mediagenda-dev : aucun Service de type LoadBalancer" \
    _m20x_kq '[.items[] | select(.spec.type == "LoadBalancer")] | length == 0' -n "$_m20x_ns_dev" services
fi
_m20_e36_overlay() { _m20x_gitlab_dossier "$_m20x_deploiement" overlays/dev; }
check_cmd "overlays/dev (main) : aucune ressource de portée cluster (ClusterRole, ClusterRoleBinding…)" \
  bash -c '! grep -Eq "^kind:[[:space:]]*(ClusterRole|ClusterRoleBinding|PriorityClass|Namespace|StorageClass)[[:space:]]*$" <<<"$1"' _ "$(_m20_e36_overlay)"
check_cmd "mediagenda/deploiement : outils/verifier-overlay.sh présent" _m20x_fichier_present mediagenda/deploiement verifier-overlay.sh
_m20_e36_job() {
  local f
  for f in .gitlab-ci.yml ci/verification-overlays.yml; do
    _m20x_gitlab_brut mediagenda/deploiement "$f" 2>/dev/null | grep -q 'verifier-overlay' && return 0
  done
  return 1
}
check_cmd "mediagenda/deploiement : job verifier-overlays dans le pipeline" _m20_e36_job
check_cmd "RB-200 : section sur la synchronisation en échec" _m20x_doc_contient "$_m20x_rb200" '^#+ .*(synchroni[sz]ation .*(échoue|échec)|Sync failed)'
check_cmd "journal de diagnostic de INC-4736 commité (docs/kubernetes/journal/)" _m20x_journal 'INC-4736'
check_cmd "panne M20-E36 close (lab/bin/break 20 36 --annuler après réparation)" _m20x_aucune_panne_active E36
