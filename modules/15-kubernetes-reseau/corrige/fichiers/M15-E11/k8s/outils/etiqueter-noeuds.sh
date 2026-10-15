#!/usr/bin/env bash
# plateforme/k8s — outils/etiqueter-noeuds.sh (M14-E14, complété en M15-E11)
# Applique cluster/noeuds.yaml : étiquettes et taints MédiSphère sur les nœuds présents.
# Idempotent (--overwrite) ; un nœud décrit mais absent du cluster est signalé, pas une erreur.
# M15-E11 : pour chaque clé de « etiquettes_gerees » (bgp), l'étiquette est RETIRÉE d'un nœud qui
# ne l'a pas dans le fichier (un nœud sorti de bgp=par1 cesse d'annoncer). Les autres étiquettes
# et les taints supprimées du fichier se retirent toujours à la main, consigné dans la MR (M14).
# Usage : outils/etiqueter-noeuds.sh [--dry-run | --verifier]     (depuis la racine du dépôt)
#   --dry-run  : kubectl en --dry-run=server ;
#   --verifier : n'écrit rien, liste les écarts sur les étiquettes, code 1 s'il y en a (M15-E23).
# Prérequis : kubectl (identité d'administration), yq (mikefarah) 4.x, jq.
set -euo pipefail

fichier="cluster/noeuds.yaml"
essai=()
verifier=0
case "${1:-}" in
  --dry-run) essai=(--dry-run=server) ;;
  --verifier) verifier=1 ;;
  "") ;;
  *) echo "usage : $0 [--dry-run | --verifier]" >&2; exit 2 ;;
esac
[[ -r "$fichier" ]] || { echo "lance-moi depuis la racine de plateforme/k8s ($fichier introuvable)" >&2; exit 1; }
derive=0

# 1. Étiquettes et taints décrites dans le fichier (comportement du M14).
for noeud in $(yq -r '.noeuds | keys | .[]' "$fichier"); do
  if ! kubectl get node "$noeud" >/dev/null 2>&1; then
    echo "absent du cluster, ignoré : $noeud"
    continue
  fi
  mapfile -t etiquettes < <(N="$noeud" yq -r '.noeuds[strenv(N)].etiquettes // {} | to_entries | .[] | .key + "=" + .value' "$fichier")
  if ((verifier)); then
    actuelles="$(kubectl get node "$noeud" -o json | jq -c '.metadata.labels')"
    for e in "${etiquettes[@]}"; do
      cle="${e%%=*}" voulue="${e#*=}"
      presente="$(jq -r --arg c "$cle" '.[$c] // ""' <<<"$actuelles")"
      if [[ "$presente" != "$voulue" ]]; then
        printf 'dérive : %s %s=%s (attendu : %s)\n' "$noeud" "$cle" "${presente:-<absente>}" "$voulue"
        derive=1
      fi
    done
    continue
  fi
  if ((${#etiquettes[@]})); then
    kubectl label node "$noeud" --overwrite "${essai[@]}" "${etiquettes[@]}"
  fi
  mapfile -t taints < <(N="$noeud" yq -r '.noeuds[strenv(N)].taints // [] | .[] | .cle + "=" + .valeur + ":" + .effet' "$fichier")
  if ((${#taints[@]})); then
    kubectl taint node "$noeud" --overwrite "${essai[@]}" "${taints[@]}"
  fi
done

# 2. Étiquettes gérées : retirées des nœuds (présents dans le cluster) qui ne les ont pas dans le fichier.
mapfile -t cles < <(yq -r '.etiquettes_gerees // [] | .[]' "$fichier")
mapfile -t presents < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
for noeud in "${presents[@]}"; do
  actuelles="$(kubectl get node "$noeud" -o json | jq -c '.metadata.labels')"
  for cle in "${cles[@]}"; do
    voulue="$(N="$noeud" C="$cle" yq -r '.noeuds[strenv(N)].etiquettes[strenv(C)] // ""' "$fichier")"
    presente="$(jq -r --arg c "$cle" '.[$c] // ""' <<<"$actuelles")"
    [[ -z "$voulue" && -n "$presente" ]] || continue
    if ((verifier)); then
      printf 'dérive : %s %s=%s (attendu : <absente>)\n' "$noeud" "$cle" "$presente"
      derive=1
    else
      kubectl label node "$noeud" "${essai[@]}" "$cle-"
    fi
  done
done

if ((verifier && derive)); then exit 1; fi
exit 0
