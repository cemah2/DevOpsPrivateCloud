# Image du service « rappels » (essai de Lucas, M19-E21). Hors du périmètre de la revue : on ne relit
# que le pipeline. Construite par le composant construction-image dans la version corrigée.
FROM registry.par1.medisphere.internal/ghcr/astral-sh/uv:0.12.23-python3.13-trixie-slim AS construction
WORKDIR /app
COPY pyproject.toml uv.lock README.md ./
COPY src/ src/
RUN uv sync --locked --no-dev --no-editable

FROM registry.par1.medisphere.internal/dockerhub/library/python:3.13-slim-trixie
RUN useradd --uid 10004 --no-create-home --shell /usr/sbin/nologin rappels
COPY --from=construction /app/.venv /app/.venv
USER 10004
ENV PATH="/app/.venv/bin:$PATH"
CMD ["python", "-c", "import labo; print('rappels prêt')"]
