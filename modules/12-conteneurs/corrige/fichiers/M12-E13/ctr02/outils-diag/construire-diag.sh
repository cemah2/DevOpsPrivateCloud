#!/usr/bin/env bash
# construire-diag.sh — image d'outils de diagnostic réseau, construite par Buildah en MODE SCRIPT
# (sans Dockerfile), sous le compte app de ctr02 (M12-E13, PLAT-1313).
#   app@ctr02:~/m12/e13$ ./construire-diag.sh            # → localhost/m12/diag:1.0
# Chaque commande buildah agit sur un conteneur de travail : on y exécute (run), on règle la
# configuration de l'image (config), puis on fige le tout en une image (commit). Aucun démon.
set -euo pipefail

version="${1:-1.0}"
base="docker.io/library/debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f"
image="localhost/m12/diag:${version}"

ctr="$(buildah from --pull=missing "$base")"
# Le conteneur de travail disparaît quoi qu'il arrive (succès, erreur, Ctrl-C).
trap 'buildah rm "$ctr" >/dev/null 2>&1 || true' EXIT

# Une seule couche pour les paquets, cache APT vidé dans la même commande (sinon il reste figé
# dans la couche, M12-E16).
buildah run "$ctr" -- sh -c '
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl bind9-dnsutils iproute2 jq netcat-openbsd
  rm -rf /var/lib/apt/lists/*'
buildah run "$ctr" -- useradd --system --uid 10050 --no-create-home --home-dir /nonexistent \
  --shell /usr/sbin/nologin diag

buildah config \
  --user 10050:10050 \
  --workingdir / \
  --cmd '["/bin/bash"]' \
  --label org.opencontainers.image.title=diag \
  --label org.opencontainers.image.description="Outils de diagnostic réseau (MédiSphère, M12-E13)" \
  --label org.opencontainers.image.version="$version" \
  --label org.opencontainers.image.vendor=MédiSphère \
  "$ctr"

# Format OCI (défaut de Buildah) ; --squash serait possible, mais on garde les couches de la base
# (partagées avec les autres images) : seule la nôtre est nouvelle.
buildah commit "$ctr" "$image"
buildah images --format '{{.Name}}:{{.Tag}} {{.Size}}' "$image"
