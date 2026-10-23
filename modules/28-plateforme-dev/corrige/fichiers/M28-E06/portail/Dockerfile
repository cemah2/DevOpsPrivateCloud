# plateforme/portail — Dockerfile (M28-E06, PLAT-2906)
# Construction MULTI-ÉTAPES de la documentation Backstage 1.56 (« Deploying with Docker », section
# « Multi-stage Build »), adaptée : bases par le cache Harbor et par empreinte, pas de dossier plugins/
# (aucun plugin interne). Construite par le démon BuildKit du cluster (composant construction-image) :
# les montages de cache (--mount=type=cache) et le « COPY --chown » exigent BuildKit.
# yarn install a besoin du registre npm (BuildKit → Internet) et apt de deb.debian.org.

# Étape 1 — squelette pour l'installation des dépendances (cache de couches)
FROM registry.par1.medisphere.internal/dockerhub/library/node:24-trixie-slim@sha256:<DIGEST-NODE-24> AS packages

WORKDIR /app
COPY backstage.json package.json yarn.lock ./
COPY .yarn ./.yarn
COPY .yarnrc.yml ./

COPY packages packages

RUN find packages \! -name "package.json" -mindepth 2 -maxdepth 2 -exec rm -rf {} \+

# Étape 2 — installation et construction
FROM registry.par1.medisphere.internal/dockerhub/library/node:24-trixie-slim@sha256:<DIGEST-NODE-24> AS build

# Dépendances natives de better-sqlite3 (base de développement local, app-config.yaml).
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /app

COPY --from=packages --chown=node:node /app .

RUN --mount=type=cache,target=/home/node/.cache/yarn,sharing=locked,uid=1000,gid=1000 \
    yarn install --immutable

COPY --chown=node:node . .

RUN yarn tsc
RUN yarn --cwd packages/backend build

RUN mkdir packages/backend/dist/skeleton packages/backend/dist/bundle \
    && tar xzf packages/backend/dist/skeleton.tar.gz -C packages/backend/dist/skeleton \
    && tar xzf packages/backend/dist/bundle.tar.gz -C packages/backend/dist/bundle

# Étape 3 — image d'exécution (dépendances de production seulement)
FROM registry.par1.medisphere.internal/dockerhub/library/node:24-trixie-slim@sha256:<DIGEST-NODE-24>

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

# Utilisateur « node » (UID 1000) de l'image Node.js. Le pod le redit en NUMÉRIQUE
# (runAsUser: 1000) : runAsNonRoot ne peut pas vérifier un nom d'utilisateur.
USER node
WORKDIR /app

COPY --from=build --chown=node:node /app/.yarn ./.yarn
COPY --from=build --chown=node:node /app/.yarnrc.yml  ./
COPY --from=build --chown=node:node /app/backstage.json ./
COPY --from=build --chown=node:node /app/yarn.lock /app/package.json /app/packages/backend/dist/skeleton/ ./

RUN --mount=type=cache,target=/home/node/.cache/yarn,sharing=locked,uid=1000,gid=1000 \
    yarn workspaces focus --all --production && rm -rf "$(yarn cache clean)"

COPY --from=build --chown=node:node /app/packages/backend/dist/bundle/ ./

COPY --chown=node:node app-config.yaml app-config.production.yaml ./

ENV NODE_ENV=production

# Le chart backstage remplace la commande par « node packages/backend » : les --config ci-dessous
# ne valent que pour un « docker run » ; dans le cluster, ils sont repris par backstage.args.
CMD ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
