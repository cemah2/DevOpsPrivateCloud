#!/usr/bin/env bash
# plateforme/k8s — outils/etiqueter-noeuds.sh (M14-E14)
# Applique cluster/noeuds.yaml : étiquettes et taints MédiSphère sur les nœuds présents.
# Idempotent (--overwrite) ; un nœud décrit mais absent du cluster est signalé, pas une erreur.
# Ne RETIRE rien : une étiquette ou une taint supprimée du fichier se retire à la main
# (kubectl label node N cle- / kubectl taint node N cle:EFFET-), consigné dans la MR.
# Usage : outils/etiqueter-noeuds.sh [--dry-run]     (depuis la racine du dépôt)
set -euo pipefail

fichier="cluster/noeuds.yaml"
essai=()
[[ "${1:-}" == "--dry-run" ]] && essai=(--dry-run=server)
[[ -r "$fichier" ]] || { echo "lance-moi depuis la racine de plateforme/k8s ($fichier introuvable)" >&2; exit 1; }

for noeud in $(yq -r '.noeuds | keys | .[]' "$fichier"); do
  if ! kubectl get node "$noeud" >/dev/null 2>&1; then
    echo "absent du cluster, ignoré : $noeud"
    continue
  fi
  mapfile -t etiquettes < <(N="$noeud" yq -r '.noeuds[strenv(N)].etiquettes // {} | to_entries | .[] | .key + "=" + .value' "$fichier")
  if ((${#etiquettes[@]})); then
    kubectl label node "$noeud" --overwrite "${essai[@]}" "${etiquettes[@]}"
  fi
  mapfile -t taints < <(N="$noeud" yq -r '.noeuds[strenv(N)].taints // [] | .[] | .cle + "=" + .valeur + ":" + .effet' "$fichier")
  if ((${#taints[@]})); then
    kubectl taint node "$noeud" --overwrite "${essai[@]}" "${taints[@]}"
  fi
done
