#!/usr/bin/env bash
# plateforme/gitops — outils/etat-applications.sh (F1-S10, PLAT-3110)
# Tableau des Applications d'Argo CD qui ne sont PAS Synced/Healthy, avec la raison lisible :
# phase de la dernière opération, premier message d'erreur, première ressource en échec, vague.
# Lecture seule. Sert pendant une convergence (reconstruction, montée de version) :
#   outils/etat-applications.sh                  # une fois
#   watch -n 60 outils/etat-applications.sh      # en continu
#   outils/etat-applications.sh --tout           # toutes les Applications
# Variables : KUBECTL_CONTEXTE (k8s-par1), ATTENTE (Applications attendues non saines, ex. en F1-S10 :
# « mediagenda-recette mediagenda-prod portail »).

set -euo pipefail

CTX="${KUBECTL_CONTEXTE:-k8s-par1}"
TOUT=0
[[ "${1:-}" == --tout ]] && TOUT=1
ATTENTE_JSON="$(jq -cn --arg a "${ATTENTE:-}" '$a | split(" ") | map(select(length > 0))')"

kubectl --context "$CTX" -n argocd get applications.argoproj.io -o json |
  jq -r --argjson tout "$TOUT" --argjson attente "$ATTENTE_JSON" '
    def raison:
      (.status.conditions // [] | map(select(.type | test("Error|Warning"))) | first | .message)
      // (.status.operationState.message)
      // ([.status.resources[]? | select((.health.status // "Healthy") != "Healthy" or .status != "Synced")
           | "\(.kind)/\(.name) \(.health.status // "") \(.health.message // "")"] | first)
      // "";
    .items
    | map(select($tout == 1 or .status.sync.status != "Synced" or .status.health.status != "Healthy"))
    | sort_by(.metadata.annotations["argocd.argoproj.io/sync-wave"] // "0" | tonumber? // 0)
    | (["APPLICATION", "SYNC", "SANTÉ", "OPÉRATION", "VAGUE", "RAISON"] | @tsv),
      (.[] | [
        (.metadata.name + (if (.metadata.name as $n | $attente | index($n)) then " (attendue)" else "" end)),
        (.status.sync.status // "?"), (.status.health.status // "?"),
        (.status.operationState.phase // "-"),
        (.metadata.annotations["argocd.argoproj.io/sync-wave"] // "0"),
        (raison | gsub("[\n\t]"; " ") | .[0:140])
      ] | @tsv)' | column -t -s $'\t'
