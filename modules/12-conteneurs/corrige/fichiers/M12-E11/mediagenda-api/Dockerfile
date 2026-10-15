# syntax=docker/dockerfile:1
# Dockerfile de MédiAgenda (projet mediagenda/api), version 0.2.0 — M12-E11, ticket PLAT-1311.
# Remplace le Dockerfile mono-étape de M12-E05 : deux étapes, cache de uv hors de l'image, jeton
# d'index en secret de construction, ni uv ni cache dans l'image livrée, construction reproductible.
#
#   admin@ctr01:~/src/mediagenda-api$ docker build --build-arg VERSION=0.2.0 \
#       --secret id=jeton_index,src=$HOME/.config/medisphere/jeton-index \
#       -t mediagenda-api:0.2.0 .
#
# Reproductible (même empreinte d'une construction à l'autre, avec ou sans cache) :
#   docker buildx build --build-arg VERSION=0.2.0 \
#       --build-arg SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) \
#       --output type=oci,dest=…,rewrite-timestamp=true .
#
# Images de base : nom complet + étiquette + empreinte d'index (relevées le 2026-10-15).
# Ce Dockerfile n'utilise pas l'option « env= » des secrets : Buildah 1.39 (ctr02, M12-E13) doit
# pouvoir le construire tel quel.

# --- Étape 1 : environnement virtuel -------------------------------------------------------------
FROM docker.io/library/python:3.13-slim-trixie@sha256:70729b46c69b4f1e97c4822c1af3df53a1476cf5ddc6c087c0c10bc3a5678c2f AS construction
# uv vient de son image officielle, version figée (PLAN §6) : ni « curl | sh » ni pip.
COPY --from=ghcr.io/astral-sh/uv:0.12.23@sha256:61d393e44e249f2e4b526b6c7ddcecce245946826e608e11c93ad4f5bba55b21 /uv /usr/local/bin/uv
# COMPILE_BYTECODE : les .pyc sont produits ici, pas au premier démarrage (racine en lecture
#   seule au M12-E24). Avec SOURCE_DATE_EPOCH, Python les produit en mode « checked-hash »
#   (empreinte du source au lieu de sa date) : ils restent valides et identiques d'une fois à l'autre.
# LINK_MODE=copy : le cache est un montage, on ne fait pas de liens physiques vers lui.
# PYTHON_DOWNLOADS=never : on utilise le Python de l'image, jamais un Python téléchargé.
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv
ARG SOURCE_DATE_EPOCH
WORKDIR /app
# 1) Les dépendances seules, d'après le verrou : couche réutilisée tant que uv.lock ne change pas.
#    - pyproject.toml et uv.lock sont MONTÉS (bind) : ils n'entrent dans aucune couche ;
#    - le cache de uv est un montage de CACHE BuildKit : il survit d'une construction à l'autre
#      sur ce constructeur, sans jamais entrer dans l'image ;
#    - le jeton de l'index privé est un SECRET de construction : un fichier sous /run/secrets/,
#      présent le temps de ce RUN seulement (ni couche, ni historique, ni cache). uv lit
#      UV_INDEX_<NOM>_PASSWORD pour l'index <nom> déclaré dans pyproject.toml ([[tool.uv.index]]) ;
#      tant qu'aucun index privé n'est déclaré, la variable est ignorée (secret facultatif).
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=secret,id=jeton_index,required=false \
    UV_INDEX_MEDISPHERE_PASSWORD="$(cat /run/secrets/jeton_index 2>/dev/null || true)" \
    uv sync --locked --no-dev --no-install-project
# 2) Le projet lui-même, installé comme un paquet (--no-editable : le code est copié DANS le venv,
#    le dossier src/ ne sert plus à l'exécution).
#    Reproductibilité : uv laisse dans le dist-info du projet un fichier interne, uv_cache.json,
#    qui porte la date de la construction (date de changement d'état des fichiers, que ni
#    SOURCE_DATE_EPOCH ni « touch » ne fixent). On le retire, avec sa ligne du RECORD (la liste des
#    fichiers installés et de leurs empreintes), pour que deux constructions donnent la même image.
COPY pyproject.toml uv.lock README.md ./
COPY src/ src/
RUN uv sync --locked --no-dev --no-editable --no-cache \
 && find /app/.venv/lib -path '*/mediagenda-*.dist-info/uv_cache.json' -delete \
 && sed -i '/uv_cache\.json,/d' /app/.venv/lib/python3.13/site-packages/mediagenda-*.dist-info/RECORD

# --- Étape 2 : exécution -------------------------------------------------------------------------
# Même image de base que l'étape 1 : le venv référence /usr/local/bin/python3.13, qui doit exister.
FROM docker.io/library/python:3.13-slim-trixie@sha256:70729b46c69b4f1e97c4822c1af3df53a1476cf5ddc6c087c0c10bc3a5678c2f
ARG VERSION=dev
# Déclaré ici aussi : useradd s'en sert pour la date de dernier changement de mot de passe de
# /etc/shadow (sinon : la date du jour, et l'empreinte change chaque jour).
ARG SOURCE_DATE_EPOCH
LABEL org.opencontainers.image.title="mediagenda-api" \
      org.opencontainers.image.description="MédiAgenda : API de prise de rendez-vous (MédiSphère)" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://git01.par1.medisphere.internal/mediagenda/api" \
      org.opencontainers.image.vendor="MédiSphère"
# Compte dédié, sans shell ni dossier personnel ; UID fixe 10001 (M12-E05), hors des comptes de l'hôte.
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
# CMD et non ENTRYPOINT : la même image lance aussi les migrations en remplaçant la commande
# (service ponctuel « migrations » de M12-E08 : « mediagenda-migrate »).
CMD ["mediagenda"]
