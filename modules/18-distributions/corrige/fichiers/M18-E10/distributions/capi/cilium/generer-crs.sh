#!/usr/bin/env bash
# capi/cilium/generer-crs.sh — rend Cilium 1.20.2 en manifeste et l'emballe dans le ConfigMap
# « cilium » du ClusterResourceSet (M18-E10). À lancer depuis adm01 (Helm 4, dépôt cilium).
#
#   admin@adm01:~/src/distributions$ capi/cilium/generer-crs.sh | kubectl --kubeconfig <gestion> apply --server-side -f -
# (--server-side : le ConfigMap dépasse les 256 Kio de l'annotation « last-applied » d'un apply classique.)
#
# Le manifeste rendu n'est PAS versionné (gros, et entièrement déterminé par la version du chart
# et values.yaml) : on versionne la recette. Pas de secret dedans (Cilium génère ses certificats
# Hubble dans le cluster).
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CILIUM_VERSION="${CILIUM_VERSION:-1.20.2}"
ESPACE="${ESPACE:-capi-essai}"
rendu="$(mktemp)"
trap 'rm -f "$rendu"' EXIT

helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update cilium >/dev/null
helm template cilium cilium/cilium --version "$CILIUM_VERSION" --namespace kube-system \
  --values "$ICI/values.yaml" > "$rendu"

kubectl create configmap cilium --namespace "$ESPACE" --from-file=data="$rendu" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - clusterctl.cluster.x-k8s.io/move="" -o yaml
