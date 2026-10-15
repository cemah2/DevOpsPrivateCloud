# syntax=docker/dockerfile:1
# Dockerfile de MédiDoc (projet medidoc/medidoc) — M12-E10, ticket DEV-1320.
# Deux étapes : on compile dans l'image Go complète, on livre le seul binaire statique dans une
# image « distroless » sans shell ni gestionnaire de paquets, sous un utilisateur non root.
#
#   docker build --build-arg VERSION=1.0.0 -t medidoc:1.0.0 .
#
# Images de base épinglées par étiquette ET par empreinte (relevées le 2026-10-08 ; à relever
# de nouveau avec « docker buildx imagetools inspect <image> » avant de les changer).

# --- Étape 1 : compilation ---------------------------------------------------------------------
FROM golang:1.26-trixie AS construction
WORKDIR /src
# Les dépendances d'abord : cette couche ne change que si go.mod ou go.sum changent.
COPY go.mod go.sum ./
RUN go mod download && go mod verify
# Puis le code (le .dockerignore écarte .git, les binaires et tout ce qui n'est pas du code).
COPY cmd/ cmd/
COPY internal/ internal/
ARG VERSION=dev
# CGO_ENABLED=0 : binaire statique, aucune dépendance à la libc (exigé par distroless/static).
# -trimpath : pas de chemins de la machine de construction dans le binaire.
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" \
      -o /out/medidoc ./cmd/medidoc

# --- Étape 2 : exécution -------------------------------------------------------------------------
# static-debian13 : certificats racines, /etc/passwd (nonroot = 65532), tzdata ; rien d'autre.
FROM gcr.io/distroless/static-debian13:nonroot
ARG VERSION=dev
LABEL org.opencontainers.image.title="medidoc" \
      org.opencontainers.image.description="MédiDoc : documents patients (MédiSphère)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/medidoc/medidoc" \
      org.opencontainers.image.vendor="MédiSphère"
COPY --from=construction /out/medidoc /usr/local/bin/medidoc
# Numérique et non nominatif : un orchestrateur peut vérifier « runAsNonRoot » sans lire /etc/passwd.
USER 65532:65532
EXPOSE 8080
# Forme « exec » : le binaire est le PID 1 et reçoit SIGTERM directement (arrêt propre, 20 s).
ENTRYPOINT ["/usr/local/bin/medidoc"]
