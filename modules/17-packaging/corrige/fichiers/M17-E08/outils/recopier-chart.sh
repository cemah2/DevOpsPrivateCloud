#!/usr/bin/env bash
# recopier-chart.sh — recopie un chart tiers dans Harbor (projet charts) et le signe, M17-E08.
# Usage : outils/recopier-chart.sh <dépôt HTTPS> <chart> <version>
#   ex. : outils/recopier-chart.sh https://valkey.io/valkey-helm/ valkey 0.12.0
# Le script s'arrête après le téléchargement pour la RELECTURE humaine (images, RBAC, hooks) :
# on ne signe que ce qu'on a lu. Mêmes prérequis que publier-chart.sh.
set -euo pipefail

registre="registry.par1.medisphere.internal"
depot="${1:?dépôt}"; chart="${2:?chart}"; version="${3:?version}"
: "${COSIGN_KEY:?COSIGN_KEY manquant}" "${COSIGN_PUB:?COSIGN_PUB manquant}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

helm pull "$chart" --repo "$depot" --version "$version" -d "$tmp"
archive="$tmp/$chart-$version.tgz"
echo "== Images citées par le rendu par défaut :"
helm template relecture "$archive" | grep -E '^[[:space:]]+image:' | sort -u
echo "== Objets RBAC et hooks :"
helm template relecture "$archive" | grep -E '^kind: (ClusterRole|ClusterRoleBinding|Role|RoleBinding)$|helm.sh/hook:' | sort | uniq -c
read -r -p "Relu, conforme ? Taper « oui » pour publier et signer : " reponse
[[ "$reponse" == "oui" ]] || { echo "abandon"; exit 1; }

helm push "$archive" "oci://$registre/charts" | tee "$tmp/push.log"
digest="$(sed -n 's/^Digest: //p' "$tmp/push.log")"
cosign sign --yes --key "$COSIGN_KEY" --use-signing-config=false --tlog-upload=false "$registre/charts/$chart@$digest"
cosign verify --key "$COSIGN_PUB" --insecure-ignore-tlog=true "$registre/charts/$chart@$digest" >/dev/null
echo "$registre/charts/$chart:$version recopié et signé : $digest"
