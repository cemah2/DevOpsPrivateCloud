# Échantillon de test du composant construction-image (M19-E10) : une image minuscule, sans RUN réseau.
FROM registry.par1.medisphere.internal/dockerhub/library/busybox:1.37
ARG VERSION=dev
LABEL org.opencontainers.image.title="echantillon-composants"
RUN echo "$VERSION" > /version
USER 65534:65534
CMD ["cat", "/version"]
