# syntax=docker/dockerfile:1
# Dockerfile de MédiDoc (projet medidoc/medidoc), multi-architectures par COMPILATION CROISÉE —
# M12-E12, ticket DEV-1312. Remplace celui de M12-E10 (même image finale, même utilisateur).
#
# L'étape de compilation tourne sur l'architecture de la machine qui construit ($BUILDPLATFORM) ;
# Go produit le binaire de l'architecture cible ($TARGETARCH) : aucune émulation QEMU, même
# vitesse pour arm64 que pour amd64. Seule l'image finale est « de la plateforme cible », et elle
# ne contient aucun RUN : rien n'y est exécuté pendant la construction.
#
#   admin@ctr01:~/src/medidoc$ docker buildx build --builder multiarch \
#       --platform linux/amd64,linux/arm64 --build-arg VERSION=1.0.0 \
#       --output type=oci,dest=$HOME/m12/e12/medidoc-1.0.0.oci.tar,name=medidoc:1.0.0 .

FROM --platform=$BUILDPLATFORM docker.io/library/golang:1.26-trixie@sha256:f06b7122f888680048afb247c4e5f49c0069eb6c4c1ccae0f3f4834527a8d22c AS construction
WORKDIR /src
# Modules Go dans un cache BuildKit (hors image), fichiers du module MONTÉS (ni copiés, ni en couche).
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=bind,source=go.mod,target=go.mod \
    --mount=type=bind,source=go.sum,target=go.sum \
    go mod download && go mod verify
# Arguments automatiques de BuildKit : à DÉCLARER dans l'étape pour y être visibles.
ARG TARGETOS TARGETARCH
ARG VERSION=dev
# Le cache de compilation (go-build) survit lui aussi aux constructions ; le code est monté.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=bind,target=. \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/medidoc ./cmd/medidoc

# Sans --platform : l'image finale est celle de la plateforme CIBLE ; l'empreinte ci-dessous est
# celle de l'INDEX de distroless, qui a une entrée par architecture (amd64, arm64…).
FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3
ARG VERSION=dev
LABEL org.opencontainers.image.title="medidoc" \
      org.opencontainers.image.description="MédiDoc : documents patients (MédiSphère)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/medidoc/medidoc" \
      org.opencontainers.image.vendor="MédiSphère"
COPY --from=construction /out/medidoc /usr/local/bin/medidoc
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/medidoc"]
