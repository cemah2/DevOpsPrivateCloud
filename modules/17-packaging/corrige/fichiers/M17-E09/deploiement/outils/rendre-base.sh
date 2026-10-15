#!/usr/bin/env bash
# rendre-base.sh — régénère base/rendu/mediagenda.yaml depuis le chart OCI signé (M17-E09).
# Usage : outils/rendre-base.sh [--verifier]
#   --verifier : ne modifie rien ; code 1 si le rendu commité diffère du rendu attendu (job de CI).
# Prérequis sur adm01 : helm 4.3, cosign 3.1, « helm registry login registry.par1.medisphere.internal »
# fait, clé publique MédiSphère dans COSIGN_PUB (défaut : MS_COSIGN_PUB du M13-E07, sinon ~/medisphere/docs/registre/cosign.pub).
set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$racine/chart.env"
cle="${COSIGN_PUB:-${MS_COSIGN_PUB:-$HOME/medisphere/docs/registre/cosign.pub}}"
sortie="$racine/base/rendu/mediagenda.yaml"
mode="${1:-rendre}"

[[ "$CHART_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "chart.env : CHART_DIGEST invalide" >&2; exit 2; }
[[ -r "$cle" ]] || { echo "clé publique Cosign illisible : $cle" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1. Récupérer la version demandée et contrôler qu'elle a le digest attendu (l'étiquette pourrait
#    avoir été republiée ; le digest, lui, désigne un contenu unique).
helm pull "$CHART_REF" --version "$CHART_VERSION" -d "$tmp" >"$tmp/pull.log"
recu="$(sed -n 's/^Digest: //p' "$tmp/pull.log")"
if [[ "$recu" != "$CHART_DIGEST" ]]; then
  echo "digest reçu ($recu) différent de chart.env ($CHART_DIGEST) : arrêt" >&2
  exit 1
fi

# 2. Vérifier la signature MédiSphère de CE digest (pas de journal de transparence public : M13).
cosign verify --key "$cle" --insecure-ignore-tlog=true \
  "${CHART_REF#oci://}@$CHART_DIGEST" >/dev/null

# 3. Rendre, sans hooks ni tests (Kustomize et kubectl ne les connaissent pas).
{
  echo "# Rendu de ${CHART_REF#oci://}:$CHART_VERSION ($CHART_DIGEST), signature vérifiée."
  echo "# Produit par outils/rendre-base.sh — ne pas modifier à la main."
  helm template mediagenda "$tmp"/mediagenda-"$CHART_VERSION".tgz \
    -f "$racine/base/values-communes.yaml" --no-hooks --skip-tests
} >"$tmp/rendu.yaml"

if [[ "$mode" == "--verifier" ]]; then
  if diff -u "$sortie" "$tmp/rendu.yaml"; then
    echo "rendu à jour"
  else
    echo "base/rendu/mediagenda.yaml ne correspond pas au chart de chart.env : relance outils/rendre-base.sh" >&2
    exit 1
  fi
else
  install -m 644 "$tmp/rendu.yaml" "$sortie"
  echo "rendu écrit : $sortie"
fi
