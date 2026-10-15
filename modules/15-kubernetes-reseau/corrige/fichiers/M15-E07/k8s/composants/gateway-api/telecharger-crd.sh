#!/usr/bin/env bash
# telecharger-crd.sh — récupère les CRD de la Gateway API (canal STANDARD) dans le dépôt (M15-E07, DEV-1607).
#
# Usage (depuis la racine de plateforme/k8s, sur adm01) :
#   composants/gateway-api/telecharger-crd.sh            # version par défaut : v1.6.1
#   composants/gateway-api/telecharger-crd.sh v1.6.3     # montée de version : nouvelle MR + SHA256SUMS
#
# Les CRD sont VERSIONNÉES dans le dépôt (composants/gateway-api/<version>/) : la MR montre ce qui
# change, l'application ne dépend pas de GitHub, et les empreintes de SHA256SUMS-<version> prouvent
# que les fichiers sont ceux publiés par le projet. Application, une fois la MR fusionnée :
#   kubectl apply --server-side -f composants/gateway-api/v1.6.1/
#
# Liste = celle qu'exige Cilium 1.20 (« Gateway API Support », Installation) ; le canal experimental
# n'est jamais installé ici (TLSRoute v1alpha2, TCPRoute, UDPRoute, ListenerSet : voir M15-E16).
set -euo pipefail

version="${1:-v1.6.1}"
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version invalide : $version (attendu vX.Y.Z)" >&2; exit 2; }

ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cible="$ici/$version"
sommes="$ici/SHA256SUMS-$version"
base="https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/$version/config/crd/standard"
ressources=(gatewayclasses gateways httproutes referencegrants grpcroutes backendtlspolicies tlsroutes)

temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

for r in "${ressources[@]}"; do
  f="gateway.networking.k8s.io_${r}.yaml"
  curl -fsS --proto '=https' --tlsv1.2 -o "$temp/$f" "$base/$f"
  # Garde-fou : un fichier du canal experimental ne doit jamais entrer par ce script.
  grep -q 'gateway.networking.k8s.io/channel: standard' "$temp/$f" \
    || { echo "$f : pas une CRD du canal standard" >&2; exit 1; }
  grep -q "gateway.networking.k8s.io/bundle-version: $version" "$temp/$f" \
    || { echo "$f : version de bundle différente de $version" >&2; exit 1; }
done

if [[ -f "$sommes" ]]; then
  (cd "$temp" && sha256sum --check --strict --quiet "$sommes")
  echo "empreintes conformes à $(basename "$sommes")"
else
  (cd "$temp" && sha256sum gateway.networking.k8s.io_*.yaml) > "$sommes"
  echo "premier téléchargement de $version : $(basename "$sommes") écrit, à faire relire dans la MR"
fi

mkdir -p "$cible"
cp "$temp"/gateway.networking.k8s.io_*.yaml "$cible/"
echo "CRD $version (canal standard) dans ${cible#"$PWD"/}"
