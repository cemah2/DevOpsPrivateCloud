#!/usr/bin/env bash
# publier-chart.sh — empaquette, publie et signe un chart dans Harbor (projet charts), M17-E08.
# Procédure manuelle de référence ; le pipeline du palier 3 (M17-E13) reprend les mêmes étapes.
# Usage : outils/publier-chart.sh charts/<chart>
# Prérequis : helm 4.3 connecté (helm registry login registry.par1.medisphere.internal),
#             cosign 3.1 connecté (cosign login, ou ~/.docker/config.json),
#             clé chargée par « . ~/src/outils/cosign-cle.sh » (M13-E07) : COSIGN_KEY (contenu de la
#             clé privée, jamais sur disque), COSIGN_PASSWORD, MS_SIGNING_CONFIG (configuration de
#             signature SANS service : docs/registre/signing-config.json), MS_COSIGN_PUB (clé publique).
set -euo pipefail

registre="registry.par1.medisphere.internal"
projet="charts"
chart_dir="${1:?usage : $0 charts/<chart>}"
: "${COSIGN_KEY:?clé absente : source ~/src/outils/cosign-cle.sh avant}"
sc="${MS_SIGNING_CONFIG:?MS_SIGNING_CONFIG absente}"
pub="${MS_COSIGN_PUB:?MS_COSIGN_PUB absente}"

nom="$(yq -r '.name' "$chart_dir/Chart.yaml")"
version="$(yq -r '.version' "$chart_dir/Chart.yaml")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1. Dépendances exactement comme dans Chart.lock (build, pas update), puis contrôles.
helm dependency build "$chart_dir"
helm lint --strict "$chart_dir" -f "$chart_dir"/ci/autonome-values.yaml
helm unittest "$chart_dir"

# 2. Archive (dépendances incluses), publication. Harbor refuse une version existante (immuabilité).
helm package "$chart_dir" -d "$tmp"
helm push "$tmp/$nom-$version.tgz" "oci://$registre/$projet" | tee "$tmp/push.log"
digest="$(sed -n 's/^Digest: //p' "$tmp/push.log")"
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "digest introuvable dans la sortie de helm push" >&2; exit 1; }

# 3. Signature PAR DIGEST, sans journal de transparence public : même méthode qu'au M13-E07
#    (configuration de signature sans service ; sans elle, Cosign 3 envoie au Rekor public).
cosign sign --key env://COSIGN_KEY --signing-config "$sc" "$registre/$projet/$nom@$digest"

# 4. Vérification immédiate avec la clé publique publiée.
cosign verify --key "$pub" --insecure-ignore-tlog=true "$registre/$projet/$nom@$digest" >/dev/null
echo "$registre/$projet/$nom:$version publié et signé : $digest"
