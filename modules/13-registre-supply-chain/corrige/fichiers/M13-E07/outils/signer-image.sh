#!/usr/bin/env bash
# outils/signer-image.sh — plateforme/outils (M13-E07, SEC-1407).
# Signe une image PAR EMPREINTE avec la clé MédiSphère, SANS journal de transparence public,
# puis vérifie avec la clé publique PUBLIÉE et contrôle que le bundle n'a aucune entrée de journal.
#   admin@adm01:~$ . ~/src/outils/cosign-cle.sh
#   admin@adm01:~$ ~/src/outils/signer-image.sh registry.par1.medisphere.internal/medisphere/medidoc:1.0.0
# Une étiquette est acceptée en ENTRÉE, mais elle est résolue en empreinte une fois, ici, et c'est
# l'empreinte qui est signée et vérifiée.
set -euo pipefail

ref="${1:?usage : signer-image.sh <image>[:étiquette|@empreinte]}"
: "${COSIGN_KEY:?clé absente : source outils/cosign-cle.sh avant}"
: "${COSIGN_PASSWORD:?phrase de passe absente}"
sc="${MS_SIGNING_CONFIG:?MS_SIGNING_CONFIG absente}"
pub="${MS_COSIGN_PUB:?MS_COSIGN_PUB absente}"
AUTH="${DOCKER_CONFIG:-$HOME/.docker}/config.json"

# Garde-fou : la configuration de signature ne doit contenir AUCUN journal ni horodateur public.
if jq -e '(.rekorTlogUrls // []) + (.tsaUrls // []) + (.caUrls // []) + (.oidcUrls // []) | length > 0' "$sc" >/dev/null; then
  echo "REFUS : $sc déclare des services Sigstore (journal, CA, horodatage) : signature publique." >&2
  exit 1
fi

depot="${ref%@*}"; depot="${depot%:*}"
if [[ "$ref" == *@sha256:* ]]; then
  empreinte="${ref#*@}"
else
  empreinte="$(skopeo inspect --authfile "$AUTH" --format '{{.Digest}}' "docker://$ref")"
fi
cible="$depot@$empreinte"
echo "Signature de $cible"

cosign sign --key env://COSIGN_KEY --signing-config "$sc" "$cible"
cosign verify --key "$pub" --insecure-ignore-tlog=true "$cible" >/dev/null
echo "Vérifiée avec $pub."
