#!/usr/bin/env bash
# occupation.sh — taux d'occupation des PVC montés de k8s-par1, lu dans le résumé de
# statistiques du kubelet de chaque nœud (M16-E11). Lecture seule.
# Usage : occupation.sh [seuil%]   (défaut 0 : tout afficher ; ex. 80 : seulement >= 80 %)
# Prérequis : kubectl (droit get sur nodes/proxy), jq.
set -euo pipefail

seuil="${1:-0}"
[[ "$seuil" =~ ^[0-9]+$ ]] || { echo "seuil invalide : $seuil" >&2; exit 2; }

printf '%-20s %-32s %-12s %8s %8s %6s\n' ESPACE PVC NOEUD UTILISE CAPACITE TAUX
for noeud in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  kubectl get --raw "/api/v1/nodes/${noeud}/proxy/stats/summary" 2>/dev/null \
    | jq -r --arg n "$noeud" --argjson s "$seuil" '
        [.pods[]? | .volume[]? | select(.pvcRef != null and (.capacityBytes // 0) > 0)
         | {e: .pvcRef.namespace, p: .pvcRef.name, u: .usedBytes, c: .capacityBytes,
            t: ((.usedBytes * 100 / .capacityBytes) | floor)}]
        | unique_by(.e + "/" + .p)[]
        | select(.t >= $s)
        | [.e, .p, $n, (.u / 1048576 | floor | tostring) + "Mi",
           (.c / 1048576 | floor | tostring) + "Mi", (.t | tostring) + "%"] | @tsv' \
    | while IFS=$'\t' read -r e p n u c t; do
        printf '%-20s %-32s %-12s %8s %8s %6s\n' "$e" "$p" "$n" "$u" "$c" "$t"
      done
done
