#!/usr/bin/env bash
# argocd-diagnostic.sh — photographie d'une Application Argo CD pour le journal de diagnostic
# (M20-E35 à M20-E43). Lecture seule : kubectl get (objets argoproj.io de l'espace argocd) et
# « argocd app diff » (compte personnel, droits de lecture suffisants).
#
#   outils/argocd-diagnostic.sh mediagenda-dev            # état, ressources non conformes, historique
#   outils/argocd-diagnostic.sh mediagenda-dev --diff     # + différences Git ↔ cluster
#
# À copier dans plateforme/outils (outils/argocd-diagnostic.sh) ; sortie collée telle quelle dans
# docs/kubernetes/journal/AAAA-MM-JJ-INC-47xx.md.
set -euo pipefail

app="${1:?usage : $0 APPLICATION [--diff]}"
ns="${ARGOCD_NS:-argocd}"
json="$(kubectl -n "$ns" get applications.argoproj.io "$app" -o json)"

printf '== %s — Application %s\n' "$(date -Is)" "$app"
jq '{
  sync: .status.sync.status, revision: .status.sync.revision, sante: .status.health,
  reconcilieeA: .status.reconciledAt,
  conditions: [.status.conditions[]? | {type, message}],
  operation: (.status.operationState // {} | {phase, message, startedAt, finishedAt,
               automatique: (.operation.initiatedBy.automated // false), revision: .syncResult.revision})
}' <<<"$json"

printf -- '\n-- Ressources non conformes (kind, espace, nom, sync, santé, élagage)\n'
jq -r '.status.resources[]?
  | select(.status != "Synced" or ((.health.status // "Healthy") != "Healthy") or (.requiresPruning // false))
  | [.kind, (.namespace // "-"), .name, .status, (.health.status // "-"),
     (if (.requiresPruning // false) then "requiresPruning" else "" end), (.health.message // "")] | @tsv' <<<"$json"

printf -- '\n-- Cinq dernières opérations\n'
jq -r '(.status.history // [])[-5:][] | [.id, (.revision // "-")[0:8], (.deployStartedAt // "-"), (.deployedAt // "-"),
  (if (.initiatedBy.automated // false) then "auto" else (.initiatedBy.username // "?") end)] | @tsv' <<<"$json"

printf -- '\n-- Ressources de l'"'"'opération en cours ou précédente qui ont échoué\n'
jq -r '.status.operationState.syncResult.resources[]? | select(.status != "Synced" or (.hookPhase // "") == "Failed")
  | [.kind, .name, .status, (.hookPhase // "-"), (.message // "")] | @tsv' <<<"$json"

if [[ "${2:-}" == --diff ]]; then
  printf -- '\n-- Différences Git ↔ cluster (argocd app diff)\n'
  argocd app diff "$app" --exit-code=false 2>&1 | head -n 300
fi
