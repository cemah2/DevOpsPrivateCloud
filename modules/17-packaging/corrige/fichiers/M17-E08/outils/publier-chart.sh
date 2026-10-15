#!/usr/bin/env bash
# publier-chart.sh — empaquette, publie et signe un chart dans Harbor (projet charts), M17-E08.
# Procédure manuelle de référence ; le pipeline du palier 3 (M17-E13) reprend les mêmes étapes.
# Usage : outils/publier-chart.sh charts/<chart>
# Prérequis : helm 4.3 connecté (helm registry login registry.par1.medisphere.internal),
#             cosign 3.1 connecté (cosign login, ou ~/.docker/config.json),
#             COSIGN_KEY = chemin ou référence de la clé privée MédiSphère (jamais dans le dépôt),
#             COSIGN_PASSWORD dans l'environnement, COSIGN_PUB = clé publique pour la vérification.
set -euo pipefail

registre="registry.par1.medisphere.internal"
projet="charts"
chart_dir="${1:?usage : $0 charts/<chart>}"
: "${COSIGN_KEY:?COSIGN_KEY manquant}" "${COSIGN_PUB:?COSIGN_PUB manquant}"

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

# 3. Signature PAR DIGEST, sans journal de transparence public (lab souverain, M13).
#    Options de Cosign 3 : voir le corrigé du M13-E07 (à aligner si ta combinaison diffère).
cosign sign --yes --key "$COSIGN_KEY" --use-signing-config=false --tlog-upload=false \
  "$registre/$projet/$nom@$digest"

# 4. Vérification immédiate avec la clé publique.
cosign verify --key "$COSIGN_PUB" --insecure-ignore-tlog=true "$registre/$projet/$nom@$digest" >/dev/null
echo "$registre/$projet/$nom:$version publié et signé : $digest"
