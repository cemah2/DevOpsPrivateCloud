# syntax=docker/dockerfile:1
#
# Dockerfile — MédiAnnuaire (projet mediagenda/annuaire), M12-E34 (CHG-1334).
# Conforme aux normes de conteneurisation (docs/conteneurs/normes.md, M12-E33) : les identifiants
# CNT-… en commentaire renvoient aux règles.
#
#   admin@ctr01:~/src/annuaire$ docker build --build-arg VERSION=1.0.0 -t annuaire:essai .
#
# CNT-IMG-01/02 : image de base du catalogue MédiSphère (M12-E27), étiquette datée ET empreinte.
# La valeur par défaut est mise à jour par MR (Renovate au M13) ; le pipeline la passe telle quelle.
ARG IMAGE_BASE=ctr01.par1.medisphere.internal:5000/bibliotheque/python:3.13-trixie-<AAAAMMJJ>@sha256:<EMPREINTE>

# --- Étape 1 : environnement virtuel, construit avec uv -----------------------------------------
FROM ${IMAGE_BASE} AS construction
# uv épinglé (même version que sur adm01, PLAN §6) : simple copie du binaire statique.
COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /src
# Le verrou d'abord : la couche des dépendances ne change que si pyproject.toml ou uv.lock changent
# (aucune dépendance aujourd'hui, mais la règle vaut pour demain).
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project
COPY README.md ./
COPY src ./src
# --no-editable : le projet est INSTALLÉ dans l'environnement ; les sources ne vont pas dans l'image finale.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

# --- Étape 2 : image d'exécution ------------------------------------------------------------------
FROM ${IMAGE_BASE}
ARG IMAGE_BASE
ARG VERSION=dev
ARG REVISION=inconnue
# CNT-IMG-06 : étiquettes OCI de provenance (la date est posée par le pipeline : --label).
LABEL org.opencontainers.image.title="mediannuaire" \
      org.opencontainers.image.description="Annuaire des praticiens de MédiSphère" \
      org.opencontainers.image.vendor="MédiSphère" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/mediagenda/annuaire" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.base.name="${IMAGE_BASE}"

# CNT-IMG-05 : utilisateur dédié, UID/GID numériques fixes, sans shell ni dossier personnel.
# Le dossier de cache existe et lui appartient (utile si la racine n'est pas en lecture seule) ;
# en recette et en production, il est remplacé par un tmpfs (CNT-RUN-05).
RUN useradd --system --uid 10003 --user-group --no-create-home --shell /usr/sbin/nologin mediannuaire \
 && install -d -o 10003 -g 10003 -m 0750 /var/cache/mediannuaire

COPY --from=construction /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    MEDIANNUAIRE_VERSION=${VERSION} \
    MEDIANNUAIRE_PORT=8080

USER 10003:10003
EXPOSE 8080
# CNT-IMG-08 : sonde intégrée à l'application (pas de curl dans l'image).
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 CMD ["mediannuaire", "sonde"]
# CNT-IMG-07 : forme exec, le processus Python est le PID 1 et reçoit SIGTERM.
STOPSIGNAL SIGTERM
CMD ["mediannuaire"]
