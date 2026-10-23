# medivisio/consultation — image (squelette Python du modèle « Nouveau service » v2, F2-S04).
# Base par le cache Harbor, épinglée par empreinte (Renovate la tient à jour, M13).
FROM registry.par1.medisphere.internal/dockerhub/library/python:3.13-slim-trixie@sha256:<DIGEST-PYTHON>
WORKDIR /app
COPY src/ ./
# Utilisateur numérique sans privilège (Pod Security « restricted »).
USER 10000:10000
EXPOSE 8080
ENTRYPOINT ["python", "-u", "app.py"]
