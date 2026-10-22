#!/usr/bin/env bash
# chronometrer-livraison.sh — du commit au pod prêt : horodatage de chaque étape (M20-E44).
# Lecture seule : API GitLab (GET, jeton read_api), objets Argo CD et pods (kubectl get), journaux
# des composants d'Argo CD (kubectl logs).
#
#   outils/chronometrer-livraison.sh mediagenda-dev
#   outils/chronometrer-livraison.sh mediagenda-dev 3f2a9c1…    (une révision précise)
#
# Étapes : commit (GitLab) → fusion de la MR → réception du webhook (argocd-server) → comparaison
# par le contrôleur → début et fin de l'opération de synchronisation → création des pods neufs →
# pods prêts. Les écarts entre étapes disent où passe le temps (attente d'interrogation sans
# webhook, file du repo-server, vagues, sondes).
set -euo pipefail

app="${1:?usage : $0 APPLICATION [RÉVISION]}"
ns_argo="${ARGOCD_NS:-argocd}"
jeton="${GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
gitlab="${GITLAB_URL:-https://git01.par1.medisphere.internal}"

a="$(kubectl -n "$ns_argo" get applications.argoproj.io "$app" -o json)"
rev="${2:-$(jq -r '.status.sync.revision' <<<"$a")}"
depot="$(jq -r '.spec.source.repoURL // .spec.sources[0].repoURL' <<<"$a" | sed -E 's#^https://[^/]+/##; s#\.git$##')"
ns_app="$(jq -r '.spec.destination.namespace' <<<"$a")"
enc() { jq -rn --arg s "$1" '$s|@uri'; }
api() { curl -sf -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(tr -d '[:space:]' <"$jeton")") "$gitlab/api/v4/$1"; }

ligne() { printf '%-34s %s\n' "$1" "${2:-?}"; }
echo "Application $app — dépôt $depot — révision ${rev:0:12}"

c="$(api "projects/$(enc "$depot")/repository/commits/$rev" 2>/dev/null || echo '{}')"
ligne "commit (committed_date)" "$(jq -r '.committed_date // empty' <<<"$c")"
mr="$(api "projects/$(enc "$depot")/repository/commits/$rev/merge_requests" 2>/dev/null || echo '[]')"
ligne "MR fusionnée (merged_at)" "$(jq -r '.[0].merged_at // empty' <<<"$mr")"
# Une fusion semi-linéaire crée un commit de fusion : c'est lui qu'Argo CD suit sur main.
ligne "révision suivie par Argo CD" "$(jq -r '.status.sync.revision' <<<"$a")"

# Webhook : l'API d'Argo CD journalise chaque événement de poussée reçu.
wh="$(kubectl -n "$ns_argo" logs deploy/argocd-server --since=24h 2>/dev/null | grep -i 'push event' | grep -F "${depot##*/}" | tail -n 1 || true)"
ligne "webhook reçu (argocd-server)" "$(jq -r '.time // empty' <<<"$wh" 2>/dev/null || echo "$wh" | cut -c1-40)"

hist="$(jq -c --arg r "$rev" '[(.status.history // [])[] | select(.revision == $r)] | last // {}' <<<"$a")"
op="$(jq -c '.status.operationState // {}' <<<"$a")"
if [[ "$(jq -r '.syncResult.revision // ""' <<<"$op")" == "$rev" ]]; then
  ligne "opération : début" "$(jq -r '.startedAt // empty' <<<"$op")"
  ligne "opération : fin ($(jq -r '.phase' <<<"$op"))" "$(jq -r '.finishedAt // empty' <<<"$op")"
else
  ligne "opération : début (historique)" "$(jq -r '.deployStartedAt // empty' <<<"$hist")"
  ligne "opération : fin (historique)" "$(jq -r '.deployedAt // empty' <<<"$hist")"
fi
ligne "dernière réconciliation" "$(jq -r '.status.reconciledAt // empty' <<<"$a")"

# Contrôleur : lignes de réconciliation de l'application (en debug, durée de chaque étape).
kubectl -n "$ns_argo" logs statefulset/argocd-application-controller --since=1h 2>/dev/null |
  grep -F "\"application\":\"$app\"" | grep -E 'Refreshing app status|Initialized new operation|operation \(phase|Skipping auto-sync|Reconciliation completed' | tail -n 8 |
  jq -r '"  contrôleur \(.time) \(.msg) \(if .time_ms then "(\(.time_ms) ms)" else "" end)"' 2>/dev/null || true

# Pods neufs : ceux du ReplicaSet le plus récent de l'application (étiquette du chart).
pods="$(kubectl -n "$ns_app" get pods -l app.kubernetes.io/name=mediagenda -o json)"
ligne "pod le plus récent : créé" "$(jq -r '[.items[].metadata.creationTimestamp] | max // empty' <<<"$pods")"
ligne "pod le plus récent : prêt" "$(jq -r '[.items[] | .status.conditions[]? | select(.type == "Ready" and .status == "True") | .lastTransitionTime] | max // empty' <<<"$pods")"
