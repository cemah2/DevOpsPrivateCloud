# syntax=docker/dockerfile:1
# Dockerfile de MédiNotif (projet medinotif/worker), version 1.0.0 — M12-E17, ticket DEV-1327.
# Le point de l'exercice : le worker doit RECEVOIR SIGTERM pour finir le message en cours,
# l'acquitter et sortir avec le code 0. Donc forme exec, pas de shell intermédiaire, signal
# d'arrêt explicite, délai de grâce plus long qu'un traitement.
#
#   docker build --build-arg VERSION=1.0.0 -t medinotif-worker:1.0.0 .

ARG PYTHON_IMAGE=python:3.13-slim-trixie

FROM ${PYTHON_IMAGE} AS construction
COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /uvx /usr/local/bin/
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=0 UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /app
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-dev --no-install-project
COPY pyproject.toml uv.lock README.md ./
COPY src/ src/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

FROM ${PYTHON_IMAGE}
ARG VERSION=dev
LABEL org.opencontainers.image.title="medinotif-worker" \
      org.opencontainers.image.description="MédiNotif : worker de notifications (MédiSphère)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/medinotif/worker" \
      org.opencontainers.image.vendor="MédiSphère"
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
# SIGTERM est le défaut de Docker ; on l'écrit pour que l'intention survive à un changement de
# moteur ou d'image de base, et pour qu'une revue le voie.
STOPSIGNAL SIGTERM
# Forme exec : « medinotif » (script du venv, interpréteur Python) est le PID 1 et reçoit le signal.
# Ni tini ni --init ne sont nécessaires : le worker installe ses gestionnaires de SIGTERM/SIGINT
# et ne crée aucun processus enfant (pas de zombies à récolter). Voir le corrigé.
ENTRYPOINT ["medinotif"]
