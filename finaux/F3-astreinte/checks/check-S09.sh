# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-S09.sh — F3-S09 « Mercredi : la livraison est bloquée » : l'analyse du canary mesure bien la
# révision canary, la recette a reçu la dernière révision de mediagenda/deploiement (Application
# synchronisée sur le dernier commit, Rollout Healthy et non abandonné), Argo CD lit les dépôts, le runner
# protégé est en ligne et rien n'attend de signature depuis plus de 15 min, santé, trace INC-5909.
# Lecture seule.

# shellcheck source=_f3-debut.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f3-debut.sh"

title "F3-S09 — La livraison arrive de nouveau en recette"
require_cmd kubectl jq curl

_f3d_s09_app="${WB_F3_APP_RECETTE:-mediagenda-recette}"
_f3d_s09_dep="${WB_F3_PROJET_DEPLOIEMENT:-mediagenda/deploiement}"
_f3d_s09_api="${WB_F3_PROJET_API:-mediagenda/api}"

check_cmd "ClusterAnalysisTemplate taux-erreur-mediagenda : requêtes sur la révision canary (rollouts_pod_template_hash)" \
  _f3d_kq '[.spec.metrics[].provider.prometheus.query // ""] | length > 0 and all(test("rollouts_pod_template_hash="))' \
  clusteranalysistemplates.argoproj.io taux-erreur-mediagenda
check_cmd "Application $_f3d_s09_app : Synced, Healthy, sans erreur de comparaison" \
  _f3d_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy" and ([.status.conditions[]? | select(.type | test("Error$"))] | length == 0)' \
  -n argocd applications.argoproj.io "$_f3d_s09_app"
_f3d_s09_tete() {
  local tete rev
  tete="$(gitlab_api "projects/$(_f3s_enc "$_f3d_s09_dep")/repository/branches/main" 2>/dev/null | jq -r '.commit.id // empty')" || return 1
  rev="$(kube -n argocd get applications.argoproj.io "$_f3d_s09_app" -o json 2>/dev/null | jq -r '.status.sync.revision // empty')" || return 1
  [[ -n "$tete" && "$tete" == "$rev" ]]
}
check_cmd "la recette est déployée depuis le dernier commit de $_f3d_s09_dep (main)" _f3d_s09_tete
check_cmd "Rollout mediagenda (recette) Healthy, non abandonné, révision stable = révision courante" \
  _f3d_kq '.status.phase == "Healthy" and (.status.abort // false) == false and .status.stableRS == .status.currentPodHash' \
  -n "$_f3d_recette" rollouts.argoproj.io mediagenda
_f3d_s09_runner() {
  kube -n gitlab-runner get deploy -o json 2>/dev/null |
    jq -e '[.items[] | select(.metadata.name | test("protege"))] | length > 0 and all(.[]; (.status.readyReplicas // 0) >= 1)' >/dev/null 2>&1
}
check_cmd "runner protégé (k8s-par1-protege) : gestionnaire prêt" _f3d_s09_runner
_f3d_s09_attente() {
  local j
  j="$(gitlab_api "projects/$(_f3s_enc "$_f3d_s09_api")/jobs?scope%5B%5D=pending&per_page=100" 2>/dev/null)" || return 1
  jq -e '[.[] | select((.tag_list // []) | index("protege")) | select((.created_at | sub("\\.[0-9]+"; "") | sub("Z$"; "Z") | fromdateiso8601? // now) < (now - 900))] | length == 0' <<<"$j" >/dev/null 2>&1
}
check_cmd "aucun job protégé de $_f3d_s09_api en attente depuis plus de 15 min" _f3d_s09_attente

check_cmd "RB-335 publié (docs/exploitation/runbooks/)" _f3d_rb_present RB-335
_f3s_sante
_f3s_trace INC-5909 1
