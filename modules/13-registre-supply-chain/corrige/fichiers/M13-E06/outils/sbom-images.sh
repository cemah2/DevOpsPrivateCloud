#!/usr/bin/env bash
# outils/sbom-images.sh — plateforme/outils (M13-E06, SEC-1406).
# Pour la dernière version (ou l'étiquette donnée) de chaque image de medisphere : résout
# l'EMPREINTE, produit une SBOM SPDX et une SBOM CycloneDX en UNE analyse Syft, puis analyse la
# SBOM SPDX avec Grype (correctifs disponibles seulement). Sorties dans un dossier (défaut ~/m13/e06).
# Authentification : fichier Docker de l'utilisateur (DOCKER_CONFIG ou ~/.docker/config.json).
#
#   admin@adm01:~$ ~/src/outils/sbom-images.sh [dossier] [étiquette]
set -euo pipefail

REG="registry.par1.medisphere.internal"
SORTIE="${1:-$HOME/m13/e06}"
ETIQ="${2:-}"
IMAGES=(mediagenda-api medidoc medinotif legacy-rdv)
for o in skopeo syft grype jq; do command -v "$o" >/dev/null || { echo "$o requis" >&2; exit 2; }; done
AUTH="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
[[ -r "$AUTH" ]] || { echo "fichier d'authentification absent : $AUTH (cosign/docker login)" >&2; exit 2; }
mkdir -p "$SORTIE"

# derniere_etiquette DÉPÔT — plus grande étiquette au format version (vX.Y.Z ou X.Y.Z).
derniere_etiquette() {
  skopeo list-tags --authfile "$AUTH" "docker://$REG/medisphere/$1" \
    | jq -r '.Tags[]' | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1
}

for img in "${IMAGES[@]}"; do
  t="${ETIQ:-$(derniere_etiquette "$img")}"
  [[ -n "$t" ]] || { echo "$img : aucune étiquette de version" >&2; continue; }
  d="$(skopeo inspect --authfile "$AUTH" --format '{{.Digest}}' "docker://$REG/medisphere/$img:$t")"
  ref="$REG/medisphere/$img@$d"
  echo "$img:$t → $d"
  syft scan "registry:$ref" --quiet \
    -o "spdx-json=$SORTIE/$img.spdx.json" \
    -o "cyclonedx-json=$SORTIE/$img.cdx.json"
  # --only-fixed : ce qui a un correctif ; code retour 0 (rapport, pas blocage).
  grype "sbom:$SORTIE/$img.spdx.json" --only-fixed -o json --file "$SORTIE/$img.grype.json" --quiet
  printf '  composants : %s ; CVE corrigeables critiques : %s\n' \
    "$(jq '.packages | length' "$SORTIE/$img.spdx.json")" \
    "$(jq '[.matches[] | select(.vulnerability.severity == "Critical")] | length' "$SORTIE/$img.grype.json")"
done
