FROM python:latest

MAINTAINER lucas.martin@medisphere.internal

ARG PYPI_TOKEN=pypi-exemple-jeton-fictif-lucas
ENV MEDIAGENDA_DB_URL=postgresql://mediagenda:Recette2026@db:5432/mediagenda
ENV MEDIAGENDA_VALKEY_URL=redis://valkey:6379/0

RUN apt-get update
RUN apt-get install -y curl vim git build-essential
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

WORKDIR /app
COPY . .

RUN UV_INDEX_MEDISPHERE_PASSWORD=$PYPI_TOKEN /root/.local/bin/uv sync
RUN chmod -R 777 /app

EXPOSE 80
CMD /root/.local/bin/uv run mediagenda
