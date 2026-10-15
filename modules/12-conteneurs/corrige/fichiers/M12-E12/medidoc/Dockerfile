# syntax=docker/dockerfile:1
# Dockerfile de MédiDoc, multi-architectures par COMPILATION CROISÉE (M12-E12, ticket DEV-1322).
# L'étape de compilation tourne sur l'architecture de la machine qui construit ($BUILDPLATFORM),
# Go produit le binaire de l'architecture cible ($TARGETARCH) : aucune émulation QEMU, même
# vitesse pour arm64 que pour amd64. Seule l'image finale est « de la plateforme cible ».
#
#   docker buildx build --platform linux/amd64,linux/arm64 --build-arg VERSION=1.0.0 \
#     --output type=oci,dest=$HOME/oci/medidoc-1.0.0.oci.tar,name=medidoc:1.0.0 .

FROM --platform=$BUILDPLATFORM golang:1.26-trixie AS construction
WORKDIR /src
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=bind,source=go.mod,target=go.mod \
    --mount=type=bind,source=go.sum,target=go.sum \
    go mod download && go mod verify
# Arguments automatiques de BuildKit (déclarés pour être visibles dans l'étape).
ARG TARGETOS TARGETARCH
ARG VERSION=dev
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=bind,target=. \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/medidoc ./cmd/medidoc

# Sans --platform : l'image finale est celle de la plateforme cible (index multi-arch de distroless).
FROM gcr.io/distroless/static-debian13:nonroot
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
