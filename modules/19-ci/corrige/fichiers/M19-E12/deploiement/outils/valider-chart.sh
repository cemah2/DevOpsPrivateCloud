#!/usr/bin/env bash
# outils/valider-chart.sh — mediagenda/deploiement (M19-E12) : rend la base avec la version du chart
# donnée par CHART_VERSION/CHART_DIGEST (au lieu de chart.env), puis rend et valide UN overlay.
# Ne modifie aucun fichier suivi par Git : la base est rendue dans une copie de travail jetable.
# La signature du digest a été vérifiée par le job chart:verifier-signature du pipeline parent.
# Usage (CI) : outils/valider-chart.sh <overlay>
# Variables : CHART_VERSION, CHART_DIGEST (pipeline amont), HARBOR_CHARTS_RO_USER/TOKEN (robot de
# lecture du groupe, non protégé), racine MédiSphère dans /etc/medisphere/ca/medisphere-root-ca.crt (runner).
set -euo pipefail

overlay="${1:?usage : $0 <overlay>}"
racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ca="${CA_RACINE:-/etc/medisphere/ca/medisphere-root-ca.crt}"
: "${CHART_VERSION:?}" "${CHART_DIGEST:?}"
[[ "$CHART_DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "CHART_DIGEST invalide" >&2; exit 2; }
# shellcheck source=/dev/null
source "$racine/chart.env"   # CHART_REF seulement ; version et digest viennent de l'amont

travail="$(mktemp -d)"
trap 'rm -rf "$travail"' EXIT
cp -a "$racine/." "$travail/"

printf '%s' "${HARBOR_CHARTS_RO_TOKEN:?}" \
  | helm registry login registry.par1.medisphere.internal --username "${HARBOR_CHARTS_RO_USER:?}" --password-stdin --ca-file "$ca"
helm pull "$CHART_REF" --version "$CHART_VERSION" -d "$travail/.chart" --ca-file "$ca" | tee "$travail/pull.log"
recu="$(sed -n 's/^Digest: //p' "$travail/pull.log")"
[[ "$recu" == "$CHART_DIGEST" ]] || { echo "digest reçu ($recu) ≠ digest annoncé ($CHART_DIGEST)" >&2; exit 1; }

{
  echo "# Rendu de validation : ${CHART_REF#oci://}:$CHART_VERSION ($CHART_DIGEST)"
  helm template mediagenda "$travail/.chart/mediagenda-$CHART_VERSION.tgz" \
    -f "$travail/base/values-communes.yaml" --no-hooks --skip-tests
} > "$travail/base/rendu/mediagenda.yaml"

mkdir -p "$racine/rendus"
kustomize build "$travail/overlays/$overlay" > "$racine/rendus/$overlay.yaml"
kubeconform -strict -summary -kubernetes-version 1.36.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "$racine/rendus/$overlay.yaml"
# Le garde-fou de livraison s'applique aussi au rendu de la nouvelle version.
(cd "$travail" && outils/verifier-livraison.sh "overlays/$overlay")
echo "overlay $overlay : chart $CHART_VERSION valide"
