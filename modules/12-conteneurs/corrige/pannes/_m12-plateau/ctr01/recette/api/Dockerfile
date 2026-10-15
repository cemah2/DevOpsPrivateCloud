# syntax=docker/dockerfile:1
# Image de recette de MédiAgenda (témoin du palier 4). Construite par « docker compose build api ».
# Ordre des couches : dépendances d'abord (elles changent rarement), code ensuite.

FROM python:3.13-slim-trixie AS construction
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project
COPY . .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

FROM python:3.13-slim-trixie
RUN useradd --system --uid 10001 --user-group --no-create-home --home-dir /app mediagenda
WORKDIR /app
COPY --from=construction /app/.venv /app/.venv
COPY migrations /app/migrations
ENV PATH=/app/.venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    MEDIAGENDA_MIGRATIONS_DIR=/app/migrations
USER 10001:10001
EXPOSE 8000
ENTRYPOINT ["python", "-m", "mediagenda"]
