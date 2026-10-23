# plateforme/ci-templates — images/outils-techdocs/Dockerfile (M28-E10, DEV-2910)
# Image des jobs TechDocs : Node.js 24 + @techdocs/cli 1.13.0 (generate, publish) + mkdocs et
# mkdocs-techdocs-core 1.7.1 dans un environnement virtuel Python. Construite et signée comme
# outils-supply-chain (M13, M25) ; publiée en registry.par1.medisphere.internal/plateforme/outils-techdocs:1.0.0.
# Les pods de job tournent en UID 1000 (M19-E24) : tout est installé à la construction, rien au job.
FROM registry.par1.medisphere.internal/dockerhub/library/node:24-trixie-slim@sha256:<DIGEST-NODE-24>

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/mkdocs \
 && /opt/mkdocs/bin/pip install --no-cache-dir "mkdocs-techdocs-core==1.7.1" \
 && npm install --global --no-fund --no-audit "@techdocs/cli@1.13.0" \
 && npm cache clean --force

ENV PATH="/opt/mkdocs/bin:${PATH}"
USER 1000:1000
