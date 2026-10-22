# plateforme/inventaire-images — Dockerfile (version corrigée, M26-E22)
# Image de base : bibliothèque MédiSphère (M12-M13 : reconstruite, analysée, signée), par condensé.
# Deux étapes : les outils de compilation ne vont jamais dans l'image finale.
ARG BASE=registry.par1.medisphere.internal/bibliotheque/python:<ETIQUETTE>@sha256:<CONDENSE>

FROM ${BASE} AS construction
WORKDIR /construction
COPY requirements.txt .
# Dépendances épinglées AVEC leurs empreintes (pip-compile --generate-hashes) : un paquet modifié
# sur l'index est refusé. Installées dans un environnement virtuel recopié tel quel.
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir --require-hashes -r requirements.txt

FROM ${BASE}
# Aucun secret ici : le jeton Harbor arrive à l'exécution (Secret créé par External Secrets depuis
# OpenBao), jamais par ARG/ENV (visible dans « docker history » et dans chaque copie de l'image).
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY --from=construction /opt/venv /opt/venv
WORKDIR /app
COPY --chown=0:0 app/ /app/
# UID/GID numériques (Pod Security et Kyverno ne vérifient qu'un nombre) ; 10004 : MédiInventaire.
USER 10004:10004
EXPOSE 8080
ENTRYPOINT ["python", "-m", "inventaire", "--port", "8080"]
