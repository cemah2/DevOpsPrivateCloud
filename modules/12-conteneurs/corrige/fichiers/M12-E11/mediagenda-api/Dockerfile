# syntax=docker/dockerfile:1
# Dockerfile de MédiAgenda (projet mediagenda/api), version 0.2.0 — M12-E11, ticket PLAT-1321.
# Remplace le Dockerfile mono-étape d'E05 : deux étapes, cache de uv, jeton d'index en secret de
# construction, aucune trace d'outil de construction dans l'image livrée.
#
#   docker build --build-arg VERSION=0.2.0 \
#     --secret id=jeton_index,src=$HOME/.config/medisphere/jeton-index \
#     -t mediagenda-api:0.2.0 .
#
# Construction reproductible : ajouter --build-arg SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
# et, à l'export, rewrite-timestamp=true (voir le corrigé).

ARG PYTHON_IMAGE=python:3.13-slim-trixie

# --- Étape 1 : environnement virtuel ----------------------------------------------------------
FROM ${PYTHON_IMAGE} AS construction
# uv vient de son image officielle, version figée (PLAN §6) : pas de « curl | sh ».
COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /uvx /usr/local/bin/
# COMPILE_BYTECODE : les .pyc sont produits ici, pas au premier démarrage (image en lecture seule).
# LINK_MODE=copy : le cache est un montage, on ne peut pas y faire de liens physiques.
# PYTHON_DOWNLOADS=0 : on utilise le Python de l'image, jamais un Python téléchargé.
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /app
# 1) Les dépendances seules, à partir du verrou : couche réutilisée tant que uv.lock ne change pas.
#    Les fichiers du projet sont MONTÉS (bind), pas copiés : ils n'entrent dans aucune couche.
#    Le cache de uv est un montage de cache BuildKit : il survit aux constructions sans entrer
#    dans l'image. Le jeton de l'index privé (fictif pour l'instant) est un secret de construction :
#    un fichier sous /run/secrets/, présent le temps du RUN seulement (ni couche, ni historique).
#    Lu par « cat » plutôt que par l'option env= de BuildKit : Buildah 1.39 (Podman 5.4, ctr02)
#    refuse env= (E13) ; la forme fichier marche avec les deux. required=false : la construction
#    passe sans jeton tant que l'index privé n'est pas déclaré dans pyproject.toml.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=secret,id=jeton_index,required=false \
    UV_INDEX_MEDISPHERE_PASSWORD="$(cat /run/secrets/jeton_index 2>/dev/null || true)" \
    uv sync --locked --no-dev --no-install-project
# 2) Le projet lui-même, installé comme un paquet (--no-editable : le code est copié dans le venv,
#    le dossier src/ n'est plus nécessaire à l'exécution).
COPY pyproject.toml uv.lock README.md ./
COPY src/ src/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

# --- Étape 2 : exécution ------------------------------------------------------------------------
# Même image de base que l'étape 1 : le venv référence /usr/local/bin/python3.13, qui doit exister.
FROM ${PYTHON_IMAGE}
ARG VERSION=dev
LABEL org.opencontainers.image.title="mediagenda-api" \
      org.opencontainers.image.description="MédiAgenda : API de prise de rendez-vous (MédiSphère)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/mediagenda/api" \
      org.opencontainers.image.vendor="MédiSphère"
# Compte dédié, sans shell ni répertoire personnel ; UID fixe (> 10000, hors des comptes de l'hôte).
RUN groupadd --system --gid 10001 mediagenda \
 && useradd --system --uid 10001 --gid mediagenda --no-create-home --home-dir /nonexistent \
      --shell /usr/sbin/nologin mediagenda
# Le venv et les migrations appartiennent à root : le processus peut les lire, pas les modifier.
COPY --from=construction /app/.venv /app/.venv
COPY migrations/ /app/migrations/
ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    MEDIAGENDA_MIGRATIONS_DIR=/app/migrations \
    MEDIAGENDA_VERSION=${VERSION}
WORKDIR /app
USER 10001:10001
EXPOSE 8000
# Forme exec : python (uvicorn) est le PID 1 et reçoit SIGTERM (arrêt propre en 20 s au plus).
# CMD et non ENTRYPOINT : la même image lance aussi les migrations, en remplaçant la commande
# (« docker run --rm … mediagenda-api:0.2.0 mediagenda-migrate », service ponctuel d'E08).
CMD ["mediagenda"]
