#!/usr/bin/env bash
# outils/etiqueter-noeuds.sh — applique les étiquettes de cluster/noeuds.yaml aux nœuds (M15-E11).
# Idempotent. Pour chaque clé de « etiquettes_gerees » : pose la valeur du fichier, ou RETIRE
# l'étiquette d'un nœud qui ne l'a pas dans le fichier (un nœud sorti de bgp=par1 cesse d'annoncer).
# Usage : outils/etiqueter-noeuds.sh [--verifier]   (--verifier : n'écrit rien, code 1 si dérive)
# Prérequis : kubectl (identité d'administration), yq (mikefarah) 4.x, jq.
set -euo pipefail

fichier="$(dirname "$0")/../cluster/noeuds.yaml"
verifier=0
[[ "${1:-}" == "--verifier" ]] && verifier=1
derive=0

mapfile -t cles < <(yq -r '.etiquettes_gerees[]' "$fichier")
mapfile -t noeuds < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

for n in "${noeuds[@]}"; do
  actuelles="$(kubectl get node "$n" -o json | jq -c '.metadata.labels')"
  for c in "${cles[@]}"; do
    voulue="$(N="$n" C="$c" yq -r '.noeuds[strenv(N)][strenv(C)] // ""' "$fichier")"
    presente="$(jq -r --arg c "$c" '.[$c] // ""' <<<"$actuelles")"
    [[ "$voulue" == "$presente" ]] && continue
    derive=1
    if (( verifier )); then
      printf 'dérive : %s %s=%s (attendu : %s)\n' "$n" "$c" "${presente:-<absente>}" "${voulue:-<absente>}"
    elif [[ -n "$voulue" ]]; then
      kubectl label node "$n" "$c=$voulue" --overwrite
    else
      kubectl label node "$n" "$c-"
    fi
  done
done

if (( verifier && derive )); then exit 1; fi
exit 0
