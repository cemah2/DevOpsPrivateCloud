# syntax=docker/dockerfile:1
#
# Dockerfile — MédiAgenda (projet GitLab mediagenda/api), version 0.1.0 (M12-E05).
#
# Volontairement SIMPLE : une seule étape de construction, l'image finale contient uv et
# le cache de compilation Python. Le multi-étapes, les montages de cache BuildKit et le
# durcissement viennent ensuite (M12-E10, E11, E24) ; les normes MédiSphère au M12-E33.
#
#   admin@ctr01:~/src/mediagenda-api$ docker build -t mediagenda-api:0.1.0 .
#
# Image de base : Python 3.13 (celui de pyproject.toml), Debian 13 « slim ». Étiquette
# précise plutôt que « latest » ; l'épinglage par empreinte (@sha256:…) est vu au M12-E04.
FROM docker.io/library/python:3.13-slim-trixie

# uv, épinglé : ce n'est PAS une étape de construction, seulement la copie d'un fichier
# depuis l'image officielle d'uv (binaire statique). Même version que sur adm01 (PLAN §6).
COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /usr/local/bin/uv

# UV_COMPILE_BYTECODE : les .pyc sont produits à la construction, pas au premier démarrage.
# UV_LINK_MODE=copy : pas de liens durs vers un cache qui n'existe plus dans l'image.
# UV_PYTHON_DOWNLOADS=never : on utilise le Python de l'image, uv n'en télécharge pas.
# PYTHONUNBUFFERED : chaque ligne de journal part tout de suite sur stdout.
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    PYTHONUNBUFFERED=1

WORKDIR /app

# 1. Les dépendances seules, d'après le verrou : cette couche ne change que si
#    pyproject.toml ou uv.lock changent (le code change bien plus souvent).
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project

# 2. Le projet lui-même (le README est déclaré dans pyproject.toml, uv_build le lit).
COPY README.md ./
COPY src ./src
COPY migrations ./migrations
RUN uv sync --locked --no-dev

# Les commandes « mediagenda » et « mediagenda-migrate » de l'environnement virtuel.
ENV PATH="/app/.venv/bin:${PATH}"

# Version affichée par /sante : fixée à la construction (--build-arg VERSION=…).
ARG VERSION=0.1.0
ENV MEDIAGENDA_VERSION=${VERSION}

# Jamais root à l'exécution : un compte système sans dossier personnel ni shell.
# UID numérique fixe : il servira pour les droits des volumes et pour « runAsUser ».
RUN useradd --system --uid 10001 --user-group --no-create-home --shell /usr/sbin/nologin mediagenda
USER 10001:10001

EXPOSE 8000

# Forme « exec » (tableau JSON) : uvicorn est le PID 1 et reçoit SIGTERM directement.
CMD ["mediagenda"]
