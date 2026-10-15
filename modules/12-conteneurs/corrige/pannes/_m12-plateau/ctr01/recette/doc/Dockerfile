# syntax=docker/dockerfile:1
# Image de recette de MédiDoc (témoin du palier 4). Construite par « docker compose build doc ».

FROM golang:1.26-trixie AS construction
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=1.0.0" -o /out/medidoc ./cmd/medidoc

FROM scratch
COPY --from=construction /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=construction /out/medidoc /medidoc
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/medidoc"]
