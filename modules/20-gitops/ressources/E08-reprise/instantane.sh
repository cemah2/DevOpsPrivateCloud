#!/usr/bin/env bash
# instantane.sh — photographie, EN LECTURE SEULE, l'état d'un Deployment avant ou après une reprise
# sous Argo CD (M20-E08) : révision, ReplicaSets, pods, gestionnaires de champs, annotation de suivi.
# Usage, sur adm01 :
#   ressources/E08-reprise/instantane.sh mediagenda-dev mediagenda > ~/m20/e08/avant.txt
#   … reprise …
#   ressources/E08-reprise/instantane.sh mediagenda-dev mediagenda > ~/m20/e08/apres.txt
#   diff ~/m20/e08/avant.txt ~/m20/e08/apres.txt
# Les lignes qui DOIVENT rester identiques sont préfixées « = » ; celles qui changent normalement
# pendant une reprise sont préfixées « ~ ». Aucune commande n'écrit dans le cluster.
set -Eeuo pipefail

ESPACE="${1:?usage : instantane.sh <espace> <deployment> [contexte]}"
DEPLOIEMENT="${2:?usage : instantane.sh <espace> <deployment> [contexte]}"
CONTEXTE="${3:-k8s-par1}"
k() { kubectl --context "$CONTEXTE" -n "$ESPACE" "$@"; }

dep="$(k get deployment "$DEPLOIEMENT" --show-managed-fields -o json)"
revision="$(jq -r '.metadata.annotations["deployment.kubernetes.io/revision"] // "?"' <<<"$dep")"
selecteur="$(jq -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")' <<<"$dep")"

printf '= révision du Deployment : %s\n' "$revision"
printf '= image(s) : %s\n' "$(jq -r '[.spec.template.spec.containers[].image] | join(" ")' <<<"$dep")"
printf '~ génération : %s\n' "$(jq -r '.metadata.generation' <<<"$dep")"
printf '~ suivi Argo CD : %s\n' "$(jq -r '.metadata.annotations["argocd.argoproj.io/tracking-id"] // "(aucun)"' <<<"$dep")"
jq -r '.metadata.managedFields[] | "~ gestionnaire : \(.manager) (\(.operation))"' <<<"$dep"
k get replicasets -l "$selecteur" -o json |
  jq -r '.items[] | "= ReplicaSet \(.metadata.name) révision \(.metadata.annotations["deployment.kubernetes.io/revision"]) créé \(.metadata.creationTimestamp) réplicas \(.spec.replicas)"'
k get pods -l "$selecteur" -o json |
  jq -r '.items[] | "= pod \(.metadata.name) créé \(.metadata.creationTimestamp) redémarrages \([.status.containerStatuses[]?.restartCount] | add // 0)"'
