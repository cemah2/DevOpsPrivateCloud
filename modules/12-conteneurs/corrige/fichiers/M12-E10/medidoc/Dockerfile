# syntax=docker/dockerfile:1
# Dockerfile de MédiDoc (projet medidoc/medidoc), version 1.0.0 — M12-E10, ticket DEV-1310.
# Deux étapes : on compile dans l'image Go complète (1,3 Go), on livre le seul binaire statique
# dans une image « distroless » (≈ 2 Mo de base) sans shell ni gestionnaire de paquets, sous un
# utilisateur non root. Remplacé en M12-E12 par la version multi-architectures (même image finale).
#
#   admin@ctr01:~/src/medidoc$ docker build --build-arg VERSION=1.0.0 -t medidoc:1.0.0 .
#
# Images de base : nom complet, étiquette ET empreinte d'index (relevées le 2026-10-15 avec
# « docker buildx imagetools inspect <image> » ; relève les tiennes, elles changent à chaque
# republication). L'étiquette documente, l'empreinte décide.

# --- Étape 1 : compilation ---------------------------------------------------------------------
FROM docker.io/library/golang:1.26-trixie@sha256:f06b7122f888680048afb247c4e5f49c0069eb6c4c1ccae0f3f4834527a8d22c AS construction
WORKDIR /src
# Les dépendances d'abord : cette couche ne change que si go.mod ou go.sum changent.
# « go mod verify » compare les modules téléchargés aux empreintes de go.sum.
COPY go.mod go.sum ./
RUN go mod download && go mod verify
# Puis le code (le .dockerignore n'a laissé entrer que cmd/ et internal/, sans les tests).
COPY cmd/ cmd/
COPY internal/ internal/
ARG VERSION=dev
# CGO_ENABLED=0 : binaire statique, aucune dépendance à la libc (exigé par distroless/static).
# -trimpath : aucun chemin de la machine de construction dans le binaire.
# -s -w : sans table des symboles ni informations de débogage (≈ 30 % de moins).
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" \
      -o /out/medidoc ./cmd/medidoc

# --- Étape 2 : exécution -----------------------------------------------------------------------
# static-debian13 : certificats racines, /etc/passwd (nonroot = 65532), /etc/group, tzdata, et
# rien d'autre (ni shell, ni libc). La variante « :nonroot » règle déjà USER 65532 ; on l'écrit
# quand même : c'est NOTRE exigence, elle ne doit pas dépendre d'un choix de l'image de base.
FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3
ARG VERSION=dev
LABEL org.opencontainers.image.title="medidoc" \
      org.opencontainers.image.description="MédiDoc : documents patients (MédiSphère)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/medidoc/medidoc" \
      org.opencontainers.image.vendor="MédiSphère"
# Le binaire appartient à root (0755) : le processus (65532) l'exécute sans pouvoir le modifier.
COPY --from=construction /out/medidoc /usr/local/bin/medidoc
# UID:GID numériques : un orchestrateur vérifie « runAsNonRoot » sans lire /etc/passwd.
USER 65532:65532
EXPOSE 8080
# Forme « exec » : le binaire est le PID 1 et reçoit SIGTERM directement (arrêt propre en 20 s).
# ENTRYPOINT et non CMD : l'image ne sait faire qu'une chose ; « docker run … medidoc:1.0.0 -h »
# passerait « -h » au binaire.
ENTRYPOINT ["/usr/local/bin/medidoc"]
