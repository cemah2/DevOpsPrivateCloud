# ${{ values.nom }} — image (squelette du modèle « nouveau service »).
FROM registry.par1.medisphere.internal/dockerhub/library/golang:1.26-trixie@sha256:<DIGEST-GOLANG> AS construction
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /service .

FROM registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim@sha256:<DIGEST-DEBIAN>
COPY --from=construction /service /usr/local/bin/service
USER 10000:10000
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/service"]
