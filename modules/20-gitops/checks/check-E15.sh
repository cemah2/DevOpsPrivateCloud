# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E15.sh — M20-E15 « Argo Rollouts : installer et premier canary ». Lecture seule : Application
# argo-rollouts, contrôleur, ConfigMap du greffon, Rollout labo (wb-checks) ; outil local.

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E15 — Argo Rollouts : installer et premier canary"
require_cmd jq kubectl curl

_e15_app="$(_m20o_app argo-rollouts)"
check_cmd "Application argo-rollouts : projet plateforme, Synced et Healthy" \
  _m20o_jq "$_e15_app" '.spec.project == "plateforme" and .status.sync.status == "Synced" and .status.health.status == "Healthy"'
check_cmd "argo-rollouts : chart tiré de Harbor (charts/argo-rollouts) à une version exacte" \
  _m20o_jq "$_e15_app" '[.spec.sources[]? | select(.repoURL == "registry.par1.medisphere.internal/charts" and .chart == "argo-rollouts"
      and (.targetRevision | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")))] | length == 1'
check_cmd "argo-rollouts : valeurs lues dans plateforme/gitops (source « ref »)" \
  _m20o_jq "$_e15_app" '([.spec.sources[]? | select(.ref != null) | .ref] | length == 1) as $r
    | $r and ([.spec.sources[]?.helm.valueFiles[]? | select(startswith("$"))] | length >= 1)'
check_cmd "argo-rollouts : ServerSideApply=true (CRD volumineuses)" \
  _m20o_jq "$_e15_app" '(.spec.syncPolicy.syncOptions // []) | index("ServerSideApply=true") != null'

_e15_ns="$(_m20o_k get namespace argo-rollouts -o json)"
check_cmd "espace argo-rollouts : Pod Security restricted appliqué" \
  _m20o_jq "$_e15_ns" '.metadata.labels["pod-security.kubernetes.io/enforce"] == "restricted"'
_e15_dep="$(_m20o_obj argo-rollouts deployment argo-rollouts)"
check_cmd "contrôleur argo-rollouts : tous les réplicas prêts" \
  _m20o_jq "$_e15_dep" '(.status.readyReplicas // 0) >= 1 and (.status.readyReplicas // 0) == (.spec.replicas // 1)'
check_cmd "contrôleur : images tirées par Harbor et épinglées par digest" \
  _m20o_jq "$_e15_dep" '[.spec.template.spec.containers[], (.spec.template.spec.initContainers // [])[] | .image]
    | length >= 2 and all(startswith("registry.par1.medisphere.internal/") and contains("@sha256:"))'
_e15_cm="$(_m20o_obj argo-rollouts configmap argo-rollouts-config)"
check_cmd "argo-rollouts-config : greffon argoproj-labs/gatewayAPI déclaré" \
  _m20o_jq "$_e15_cm" '.data.trafficRouterPlugins // "" | test("argoproj-labs/gatewayAPI")'
check_cmd "argo-rollouts-config : greffon chargé depuis le conteneur (file://), pas depuis Internet" \
  _m20o_jq "$_e15_cm" '.data.trafficRouterPlugins // "" | test("location: *\"?file://") and (test("github\\.com") | not)'
# Le contrôleur ne démarre pas si un greffon déclaré est introuvable : pods prêts + conteneur
# d'initialisation terminé en 0 = greffon copié puis chargé.
_e15_pods="$(_m20o_k get pods -n argo-rollouts -l app.kubernetes.io/name=argo-rollouts -o json)"
check_cmd "pods du contrôleur : copie du greffon réussie (conteneur d'initialisation terminé, code 0)" \
  _m20o_jq "$_e15_pods" '(.items | length) > 0 and ([.items[].status.initContainerStatuses[]? | .state.terminated.exitCode == 0] | (length > 0 and all))'

if _m20o_lisible rollouts.argoproj.io wb-essais; then
  check_cmd "wb-checks lit les objets d'Argo Rollouts (rollouts, analysisruns)" _m20o_lisible analysisruns.argoproj.io wb-essais
  _e15_ro="$(_m20o_obj wb-essais rollouts.argoproj.io labo)"
  check_cmd "Rollout wb-essais/labo : stratégie canary avec au moins une pause" \
    _m20o_jq "$_e15_ro" '[.spec.strategy.canary.steps[]? | select(has("pause"))] | length >= 1'
  check_cmd "Rollout labo : au moins une révision livrée en canary (révision ≥ 2)" \
    _m20o_jq "$_e15_ro" '(.metadata.annotations["rollout.argoproj.io/revision"] // "0" | tonumber) >= 2'
  check_cmd "Rollout labo : Healthy, dernière révision promue (stable = courante)" \
    _m20o_jq "$_e15_ro" '.status.phase == "Healthy" and .status.stableRS == .status.currentPodHash'
  check_cmd "wb-essais : plus de Deployment labo (remplacé par le Rollout)" \
    bash -c '[[ -z "$1" ]]' _ "$(_m20o_obj wb-essais deployment labo)"
  _e15_hpa="$(_m20o_obj wb-essais horizontalpodautoscaler labo)"
  check_cmd "HPA labo : vise le Rollout" _m20o_jq "$_e15_hpa" '.spec.scaleTargetRef.kind == "Rollout"'
else
  check_cmd "wb-checks lit les Rollouts (bloc M20-E15 de wb-checks-livraison)" false
fi
check_cmd "adm01 : kubectl argo rollouts installé (1.10)" \
  bash -c 'kubectl-argo-rollouts version 2>/dev/null | grep -q "v1\.10\."'
