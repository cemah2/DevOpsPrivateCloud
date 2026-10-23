# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
#
# check-E02.sh — M28-E02 : HPA : MédiAgenda suit sa charge
# Lecture seule : HPA, Rollout (gestionnaires de champs), pods (kube) ; Applications Argo CD ;
# historique des réplicas désirés (Prometheus, kube-state-metrics) ; dépôts GitLab en GET.
# Rejouable après le palier 3 (bornes ou comportement ajustés : seuls les invariants sont contrôlés).

# shellcheck source=_m28-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-decouverte.sh"

title "M28-E02 — HPA : MédiAgenda suit sa charge"
require_cmd jq kubectl curl

for _m28d_e02_env in recette prod; do
  _m28d_e02_ns="mediagenda-$_m28d_e02_env"
  _m28d_e02_min=2
  [[ "$_m28d_e02_env" == prod ]] && _m28d_e02_min=3
  check_cmd "$_m28d_e02_ns : HPA mediagenda vise le Rollout mediagenda (argoproj.io/v1alpha1)" _m28d_kq \
    '.spec.scaleTargetRef.kind == "Rollout" and .spec.scaleTargetRef.apiVersion == "argoproj.io/v1alpha1" and .spec.scaleTargetRef.name == "mediagenda"' \
    -n "$_m28d_e02_ns" horizontalpodautoscalers.autoscaling mediagenda
  check_cmd "$_m28d_e02_ns : métrique CPU en pourcentage des requests (Utilization)" _m28d_kq \
    '[.spec.metrics[]? | select(.type == "Resource" and .resource.name == "cpu" and .resource.target.type == "Utilization")] | length == 1' \
    -n "$_m28d_e02_ns" horizontalpodautoscalers.autoscaling mediagenda
  check_cmd "$_m28d_e02_ns : minReplicas ≥ $_m28d_e02_min et maxReplicas > minReplicas" _m28d_kq \
    '(.spec.minReplicas // 1) >= ($min | tonumber) and .spec.maxReplicas > (.spec.minReplicas // 1)' \
    -n "$_m28d_e02_ns" horizontalpodautoscalers.autoscaling mediagenda -- --arg min "$_m28d_e02_min"
  check_cmd "$_m28d_e02_ns : behavior écrit (descente stabilisée ≥ 60 s et bornée par une politique)" _m28d_kq \
    '(.spec.behavior.scaleDown.stabilizationWindowSeconds // -1) >= 60 and ((.spec.behavior.scaleDown.policies // []) | length >= 1)' \
    -n "$_m28d_e02_ns" horizontalpodautoscalers.autoscaling mediagenda
  check_cmd "$_m28d_e02_ns : condition ScalingActive vraie (la métrique CPU se calcule)" _m28d_kq \
    '[.status.conditions[]? | select(.type == "ScalingActive" and .status == "True")] | length == 1' \
    -n "$_m28d_e02_ns" horizontalpodautoscalers.autoscaling mediagenda
  check_cmd "$_m28d_e02_ns : chaque conteneur des pods de l'API a une request CPU" _m28d_kq \
    '(.items | length > 0) and all(.items[]; all(.spec.containers[]; .resources.requests.cpu != null))' \
    -n "$_m28d_e02_ns" pods -l app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api
  check_cmd "$_m28d_e02_ns : Argo CD ne possède plus spec.replicas du Rollout (Git ne le déclare plus)" \
    _m28d_replicas_hors_argocd "$_m28d_e02_ns" rollouts.argoproj.io mediagenda
  check_cmd "Application mediagenda-$_m28d_e02_env : Synced" _m28d_app_synced "mediagenda-$_m28d_e02_env"
done

check_cmd "recette : l'HPA a demandé plus que son minimum dans les dernières 24 h (essai de charge)" _m28d_prom_positif \
  'max(max_over_time(kube_horizontalpodautoscaler_status_desired_replicas{namespace="mediagenda-recette", horizontalpodautoscaler="mediagenda"}[24h]))
   - max(kube_horizontalpodautoscaler_spec_min_replicas{namespace="mediagenda-recette", horizontalpodautoscaler="mediagenda"})'
check_cmd "recette : revenu au minimum (réplicas désirés = minReplicas maintenant ; relance après la fin de la charge)" _m28d_kq \
  '.status.desiredReplicas == (.spec.minReplicas // 1)' -n mediagenda-recette horizontalpodautoscalers.autoscaling mediagenda

check_cmd "mediagenda/deploiement (main) : components/autoscaling/hpa.yaml vise le Rollout" \
  _m28d_contient mediagenda/deploiement components/autoscaling/hpa.yaml 'kind: *Rollout' 'behavior'
check_cmd "plateforme/medisphere : docs/plateforme-dev/autoscaling.md (requests, behavior, ordre des MR)" \
  _m28d_doc docs/plateforme-dev/autoscaling.md 'requests' 'behavior|stabili' 'managedFields|gestionnaire|ignoreDifferences'
