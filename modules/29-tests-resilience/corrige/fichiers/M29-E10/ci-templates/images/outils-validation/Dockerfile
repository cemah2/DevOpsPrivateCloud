# syntax=docker/dockerfile:1
#
# Image des jobs du composant « validation » (M29-E10, PLAT-3010) :
#   registry.par1.medisphere.internal/plateforme/outils-validation:<version>
# Même règles que outils-supply-chain (M13-E09) : base MédiSphère, chaque binaire épinglé par
# version ET par SHA-256 (relevés le 23/10/2026 dans les fichiers de sommes des publications
# amont et recalculés sur les archives), shell présent (l'exécuteur Kubernetes en a besoin),
# utilisateur non root. Construite par le composant construction-image, signée par securite.

FROM registry.par1.medisphere.internal/bibliotheque/debian:trixie-<AAAAMMJJ>@sha256:<EMPREINTE>

# kubeconform : CHECKSUMS de la v0.8.0 (kubeconform-linux-amd64.tar.gz)
ARG KUBECONFORM_VERSION=0.8.0
ARG KUBECONFORM_SHA256=9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883
# conftest : checksums.txt de la v0.71.1 (conftest_0.71.1_Linux_x86_64.tar.gz) ; embarque OPA 1.21.1
ARG CONFTEST_VERSION=0.71.1
ARG CONFTEST_SHA256=c3f6b2a753bd56e377a1e51a95ae3e057f926f2e9139f7d5b5dfbbaf810f7985
# opa : opa_linux_amd64_static.sha256 de la v1.21.3
ARG OPA_VERSION=1.21.3
ARG OPA_SHA256=add7c9dcf56e1ce1538426a6ee595ea1cc7ee830bbedd4c23219825b02b19a79
# kustomize : checksums.txt de kustomize/v5.8.1 (kustomize_v5.8.1_linux_amd64.tar.gz)
ARG KUSTOMIZE_VERSION=5.8.1
ARG KUSTOMIZE_SHA256=029a7f0f4e1932c52a0476cf02a0fd855c0bb85694b82c338fc648dcb53a819d
# helm : helm-v4.3.1-linux-amd64.tar.gz.sha256sum
ARG HELM_VERSION=4.3.1
ARG HELM_SHA256=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b
# yq (mikefarah) : fichier « checksums » de la v4.54.1, colonne SHA-256 (19e, voir checksums_hashes_order)
ARG YQ_VERSION=4.54.1
ARG YQ_SHA256=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl git jq python3 python3-yaml; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; cd /tmp; \
    verifier() { printf '%s  %s\n' "$1" "$2" | sha256sum -c -; }; \
    curl -fsSLO "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz"; \
    verifier "$KUBECONFORM_SHA256" kubeconform-linux-amd64.tar.gz; \
    tar -xzf kubeconform-linux-amd64.tar.gz kubeconform; \
    curl -fsSLO "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz"; \
    verifier "$CONFTEST_SHA256" "conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz"; \
    tar -xzf "conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" conftest; \
    curl -fsSLo opa "https://github.com/open-policy-agent/opa/releases/download/v${OPA_VERSION}/opa_linux_amd64_static"; \
    verifier "$OPA_SHA256" opa; \
    curl -fsSLO "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"; \
    verifier "$KUSTOMIZE_SHA256" "kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"; \
    tar -xzf "kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" kustomize; \
    curl -fsSLO "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz"; \
    verifier "$HELM_SHA256" "helm-v${HELM_VERSION}-linux-amd64.tar.gz"; \
    tar -xzf "helm-v${HELM_VERSION}-linux-amd64.tar.gz" --strip-components=1 linux-amd64/helm; \
    curl -fsSLo yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64"; \
    verifier "$YQ_SHA256" yq; \
    install -m 0755 kubeconform conftest opa kustomize helm yq /usr/local/bin/; \
    rm -f ./*.tar.gz kubeconform conftest opa kustomize helm yq; \
    kubeconform -v; conftest --version; opa version; kustomize version; helm version --short; yq --version

# Cache de Helm dans un dossier inscriptible par l'utilisateur du job.
ENV HELM_CACHE_HOME=/tmp/helm/cache HELM_CONFIG_HOME=/tmp/helm/config HELM_DATA_HOME=/tmp/helm/data

USER 10001:10001
LABEL org.opencontainers.image.description="kubeconform, conftest, opa, kustomize, helm, yq pour le composant CI/CD validation de MédiSphère"
