# syntax=docker/dockerfile:1
#
# bibliotheque/python — Python 3.13 (Debian 13 slim) de MédiSphère (M12-E27, PLAT-1353).
# Base des images de MédiAgenda, MédiNotif, MédiAnnuaire. Empreinte relevée le 2026-10-08.
ARG AMONT=docker.io/library/python:3.13-slim-trixie@sha256:bf44cdfcb76cd3b41e879bc058fc37ec5872002ccfde7fcb765e218cde0cd79c
FROM ${AMONT}
ARG AMONT
ARG REVISION=inconnue
ARG DATE_CONSTRUCTION=inconnue

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY pki/medisphere-root-ca.crt /usr/local/share/ca-certificates/medisphere-root-ca.crt
# hadolint ignore=DL3005,DL3008
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && update-ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*
# Python lit le magasin système (ssl) ; pour les bibliothèques qui embarquent le leur (certifi,
# requests), on pointe vers le magasin système, qui contient la racine MédiSphère.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    PYTHONUNBUFFERED=1

LABEL org.opencontainers.image.title="bibliotheque/python" \
      org.opencontainers.image.description="Python 3.13 MédiSphère : correctifs du jour, racine PKI" \
      org.opencontainers.image.vendor="MédiSphère" \
      org.opencontainers.image.version="3.13-trixie-${DATE_CONSTRUCTION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/plateforme/images-base" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${DATE_CONSTRUCTION}" \
      org.opencontainers.image.base.name="${AMONT}"
# hadolint ignore=DL3002
USER 0
