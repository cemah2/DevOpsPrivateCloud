# syntax=docker/dockerfile:1
# Dockerfile de MédiNotif (projet medinotif/worker), version 1.0.0 — M12-E17, ticket DEV-1317.
# Le point de l'exercice : le worker doit RECEVOIR SIGTERM pour finir le message en cours,
# l'acquitter et sortir avec le code 0. Donc : forme exec, aucun shell intermédiaire, signal
# d'arrêt explicite, et un délai de grâce (côté plateforme) plus long qu'un traitement.
#
#   admin@ctr01:~/src/medinotif-worker$ docker build --build-arg VERSION=1.0.0 -t medinotif-worker:1.0.0 .

# --- Étape 1 : environnement virtuel (même méthode que MédiAgenda, M12-E11) ------------------------
FROM docker.io/library/python:3.13-slim-trixie@sha256:70729b46c69b4f1e97c4822c1af3df53a1476cf5ddc6c087c0c10bc3a5678c2f AS construction
COPY --from=ghcr.io/astral-sh/uv:0.12.23@sha256:61d393e44e249f2e4b526b6c7ddcecce245946826e608e11c93ad4f5bba55b21 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /app
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-dev --no-install-project
COPY pyproject.toml uv.lock README.md ./
COPY src/ src/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

# --- Étape 2 : exécution -------------------------------------------------------------------------
FROM docker.io/library/python:3.13-slim-trixie@sha256:70729b46c69b4f1e97c4822c1af3df53a1476cf5ddc6c087c0c10bc3a5678c2f
ARG VERSION=dev
LABEL org.opencontainers.image.title="medinotif-worker" \
      org.opencontainers.image.description="MédiNotif : worker de notifications (MédiSphère)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/medinotif/worker" \
      org.opencontainers.image.vendor="MédiSphère"
# UID 10002 : distinct de celui de MédiAgenda (10001), pour lire sans ambiguïté qui est qui vu de
# l'hôte (ps, fichiers des volumes).
RUN groupadd --system --gid 10002 medinotif \
 && useradd --system --uid 10002 --gid medinotif --no-create-home --home-dir /nonexistent \
      --shell /usr/sbin/nologin medinotif
COPY --from=construction /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    MEDINOTIF_VERSION=${VERSION}
WORKDIR /app
USER 10002:10002
# Port des métriques Prometheus (et sonde de vivacité : il répond sur n'importe quel chemin).
EXPOSE 9100
# Vivacité : le serveur de métriques répond. Python de l'image, pas de curl (M12-E08).
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9100/metrics', timeout=2)"]
# SIGTERM est déjà le défaut de Docker et de Podman ; on l'écrit pour que l'intention survive à un
# changement de moteur, d'image de base ou de plateforme, et pour qu'une revue le voie.
STOPSIGNAL SIGTERM
# Forme exec : « medinotif » (script du venv, interpréteur Python) est le PID 1 et reçoit le signal.
# Ni tini ni --init : le worker installe ses gestionnaires de SIGTERM/SIGINT et ne lance aucun
# processus enfant (pas de zombies à récolter). Voir le corrigé pour le cas où il en faudrait un.
ENTRYPOINT ["medinotif"]
