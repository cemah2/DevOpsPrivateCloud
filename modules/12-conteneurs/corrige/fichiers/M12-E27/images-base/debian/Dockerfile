# syntax=docker/dockerfile:1
#
# bibliotheque/debian — Debian 13 minimal de MédiSphère (M12-E27, PLAT-1353).
# Amont épinglé par empreinte (changement = MR) ; reconstruit chaque semaine par le pipeline planifié
# pour embarquer les correctifs de sécurité publiés depuis.
#
# Empreinte de l'index amont relevée le 2026-10-08 (docker buildx imagetools inspect debian:trixie-slim).
ARG AMONT=docker.io/library/debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
FROM ${AMONT}
ARG AMONT
ARG REVISION=inconnue
ARG DATE_CONSTRUCTION=inconnue

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# Racine de la PKI MédiSphère (certificat PUBLIC) : toute image dérivée fait confiance au registre,
# à git01, à s3-01… sans configuration supplémentaire.
COPY pki/medisphere-root-ca.crt /usr/local/share/ca-certificates/medisphere-root-ca.crt
# Correctifs de sécurité du jour (raison d'être de la reconstruction hebdomadaire) + le strict
# nécessaire commun à TOUTES les images dérivées : certificats et fuseaux horaires.
# hadolint ignore=DL3005,DL3008
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && update-ca-certificates \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*
# DL3005 (upgrade) : voulu, c'est l'objet de l'image. DL3008 (versions apt non épinglées) : voulu,
# on prend les dernières versions de sécurité ; la traçabilité est l'étiquette datée de l'image.

LABEL org.opencontainers.image.title="bibliotheque/debian" \
      org.opencontainers.image.description="Debian 13 minimal MédiSphère : correctifs du jour, racine PKI, tzdata" \
      org.opencontainers.image.vendor="MédiSphère" \
      org.opencontainers.image.version="trixie-${DATE_CONSTRUCTION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/plateforme/images-base" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${DATE_CONSTRUCTION}" \
      org.opencontainers.image.base.name="${AMONT}"
# USER 0 explicite : image de BASE, les images dérivées installent des paquets avant de fixer LEUR
# utilisateur (norme CNT-IMG-05, contrôlée par Hadolint DL3002 sur les images d'application).
# hadolint ignore=DL3002
USER 0
