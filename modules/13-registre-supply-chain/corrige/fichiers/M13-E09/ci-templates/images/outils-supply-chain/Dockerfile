# syntax=docker/dockerfile:1
#
# Image outillée de la chaîne de livraison (M13-E09, DEV-1409) :
#   registry.par1.medisphere.internal/plateforme/outils-supply-chain:<version>
# Pourquoi une image à nous : les images officielles de Cosign et de Syft n'ont pas de shell (un
# job GitLab de l'exécuteur Docker en a besoin), et une image « latest » d'un outil de sécurité est
# exactement ce que l'incident Trivy de mars 2026 nous a appris à refuser. Ici, chaque paquet est
# épinglé par version ET par SHA-256 (empreintes relevées après vérification Sigstore manuelle,
# mêmes valeurs que le rôle Ansible outils_supply_chain, M13-E05/E06).
# Contient aussi la racine MédiSphère, la clé PUBLIQUE de signature et la configuration de
# signature sans journal : une rotation de clé = une nouvelle version de cette image.
#
# Construite par le pipeline de plateforme/ci-templates (job « outils-supply-chain »), publiée
# dans le projet Harbor « plateforme », signée. Première version : construite par le gabarit
# image.yml (M12-E21) puis signée à la main (outils/signer-image.sh), faute de chaîne existante.

FROM registry.par1.medisphere.internal/bibliotheque/debian:trixie-slim@sha256:<EMPREINTE>

ARG COSIGN_VERSION=3.1.3
ARG COSIGN_SHA256=75357d96161da4d06d37c4b2831fa6978483cdce661999e5951b586f9ee1d710
ARG TRIVY_VERSION=0.75.0
ARG TRIVY_SHA256=b6d7b944b6cbf4e7de5b4bc6c3635900c50fed53b64b77b99a5fbc3136cd1d5d
ARG SYFT_VERSION=1.54.1
ARG SYFT_SHA256=2d1b572980c5f017c55138e62d9493392c77968815025d91de90ba54998e74bb
ARG GRYPE_VERSION=0.120.1
ARG GRYPE_SHA256=111189f61433426af29cc3db33c6847d7e5272150926396b170a985fcda3a11c

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq skopeo \
 && rm -rf /var/lib/apt/lists/*

# Paquets des outils : téléchargés, vérifiés par SHA-256, installés, supprimés.
RUN set -eux; cd /tmp; \
    gh=https://github.com; \
    curl -fsSLO "$gh/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign_${COSIGN_VERSION}_amd64.deb"; \
    curl -fsSLO "$gh/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.deb"; \
    curl -fsSLO "$gh/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_amd64.deb"; \
    curl -fsSLO "$gh/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_linux_amd64.deb"; \
    printf '%s  %s\n' \
      "$COSIGN_SHA256" "cosign_${COSIGN_VERSION}_amd64.deb" \
      "$TRIVY_SHA256" "trivy_${TRIVY_VERSION}_Linux-64bit.deb" \
      "$SYFT_SHA256" "syft_${SYFT_VERSION}_linux_amd64.deb" \
      "$GRYPE_SHA256" "grype_${GRYPE_VERSION}_linux_amd64.deb" | sha256sum -c -; \
    dpkg -i ./*.deb; rm -f ./*.deb; \
    cosign version >/dev/null; trivy --version; syft version; grype version

# Racine MédiSphère (Harbor, GitLab), clé publique et configuration de signature (docs/registre/).
COPY medisphere-root-ca.crt /usr/local/share/ca-certificates/medisphere-root-ca.crt
RUN update-ca-certificates
COPY cosign.pub signing-config.json /etc/medisphere/

# Jamais root à l'exécution ; HOME inscriptible pour les caches des outils.
RUN useradd --system --uid 10001 --user-group --create-home --home-dir /home/outils --shell /bin/bash outils
USER 10001:10001
WORKDIR /home/outils
ENV TRIVY_CACHE_DIR=/home/outils/.cache/trivy \
    GRYPE_DB_CACHE_DIR=/home/outils/.cache/grype

LABEL org.opencontainers.image.title="outils-supply-chain" \
      org.opencontainers.image.description="Cosign, Trivy, Syft, Grype, Skopeo pour la chaîne de livraison MédiSphère" \
      org.opencontainers.image.vendor="MédiSphère"
