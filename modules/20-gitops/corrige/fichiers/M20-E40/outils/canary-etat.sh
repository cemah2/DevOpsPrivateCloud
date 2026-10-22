#!/usr/bin/env bash
# canary-etat.sh — photographie d'un canary Argo Rollouts (M20-E40). Lecture seule.
#
#   outils/canary-etat.sh mediagenda-recette [mediagenda]
#
# Rollout (phase, étape, pause, interruption, message), AnalysisRuns récents et leurs mesures en
# échec, poids réels de la HTTPRoute, contrôleur et greffon, opérations récentes d'Argo CD sur
# l'Application qui porte le Rollout.
set -euo pipefail

ns="${1:?usage : $0 ESPACE [ROLLOUT]}"
ro="${2:-mediagenda}"

echo "== Rollout $ns/$ro"
kubectl -n "$ns" get rollouts.argoproj.io "$ro" -o json | jq '{
  phase: .status.phase, message: .status.message, etape: .status.currentStepIndex,
  pause: (.spec.paused // false), conditionsDePause: .status.pauseConditions,
  interrompu: (.status.abort // false), stable: .status.stableRS, courant: .status.currentPodHash,
  poids: .status.canary.weights}'
if command -v kubectl-argo-rollouts >/dev/null; then
  kubectl argo rollouts get rollout "$ro" -n "$ns" --no-color | head -n 40
fi

echo
echo "== AnalysisRuns récents"
kubectl -n "$ns" get analysisruns.argoproj.io --sort-by=.metadata.creationTimestamp -o json | jq -r '
  .items[-5:][] | "\(.metadata.creationTimestamp)\t\(.metadata.name)\t\(.status.phase // "?")\t\(.status.message // "")"'
kubectl -n "$ns" get analysisruns.argoproj.io --sort-by=.metadata.creationTimestamp -o json | jq '
  .items[-1].status.metricResults[]? | {nom: .name, phase, echecs: .failed, erreurs: .error,
   dernieres: [.measurements[-3:][]? | {phase, valeur: .value, message}]}'

echo
echo "== Poids réels de la HTTPRoute $ro"
kubectl -n "$ns" get httproutes.gateway.networking.k8s.io "$ro" -o json | jq -r '
  .spec.rules[].backendRefs[]? | "\(.name)\t\(.weight // 1)"'

echo
echo "== Contrôleur Argo Rollouts et greffon"
kubectl -n argo-rollouts get pods -l app.kubernetes.io/name=argo-rollouts -o wide
kubectl -n argo-rollouts get configmap argo-rollouts-config -o jsonpath='{.data.trafficRouterPlugins}{"\n"}'
kubectl -n argo-rollouts logs -l app.kubernetes.io/name=argo-rollouts --tail=20 --prefix 2>/dev/null | grep -Ei 'plugin|error|level=error' || true

echo
echo "== Synchronisations récentes de l'Application qui porte $ns"
kubectl -n argocd get applications.argoproj.io -o json | jq -r --arg ns "$ns" '
  .items[] | select(.spec.destination.namespace == $ns) | .metadata.name as $a
  | (.status.history // [])[-5:][] | "\($a)\t\(.deployStartedAt)\t\(if (.initiatedBy.automated // false) then "auto" else (.initiatedBy.username // "?") end)\t\((.revision // "")[0:8])"'
