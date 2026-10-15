FROM golang:1.26

ADD https://github.com/aws/aws-cli/archive/refs/heads/v2.zip /tmp/awscli.zip

WORKDIR /go/src/medidoc
COPY . .
RUN go build -o /usr/local/bin/medidoc ./cmd/medidoc

ENV AWS_ACCESS_KEY_ID=MEDIDOCRECETTE
ENV AWS_SECRET_ACCESS_KEY=exemple-cle-secrete-de-recette-0123456789
ENV MEDIDOC_S3_ENDPOINT=https://s3-01.par1.medisphere.internal:8333
ENV MEDIDOC_S3_BUCKET=medidoc-recette

EXPOSE 8080
HEALTHCHECK CMD curl -f http://localhost:8080/readyz || exit 1
ENTRYPOINT medidoc
