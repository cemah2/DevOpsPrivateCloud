# syntax=docker/dockerfile:1
#
# bibliotheque/php-apache — PHP 8.4 + Apache (Debian 13) pour Legacy-RDV (M12-E27, PLAT-1353).
# Choix : Legacy-RDV est la seule application PHP ; une image commune lui donne les correctifs
# hebdomadaires sans que son Dockerfile (E19) ait à les gérer. Empreinte relevée le 2026-10-08.
# (Pour la construction Go, MédiDoc part de golang:1.26-trixie et finit sur distroless :
#  l'image finale n'a pas de paquets à corriger, l'image de construction ne part pas en production.)
ARG AMONT=docker.io/library/php:8.4-apache-trixie@sha256:901b0dbcd2419cc9cd307ea05e57403449ce722ccd5b32335da6e8d39f2b1ee0
FROM ${AMONT}
ARG AMONT
ARG REVISION=inconnue
ARG DATE_CONSTRUCTION=inconnue

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY pki/medisphere-root-ca.crt /usr/local/share/ca-certificates/medisphere-root-ca.crt
# hadolint ignore=DL3005,DL3008
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends ca-certificates \
 && update-ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

LABEL org.opencontainers.image.title="bibliotheque/php-apache" \
      org.opencontainers.image.description="PHP 8.4 + Apache MédiSphère : correctifs du jour, racine PKI" \
      org.opencontainers.image.vendor="MédiSphère" \
      org.opencontainers.image.version="8.4-apache-trixie-${DATE_CONSTRUCTION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/plateforme/images-base" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${DATE_CONSTRUCTION}" \
      org.opencontainers.image.base.name="${AMONT}"
# hadolint ignore=DL3002
USER 0
