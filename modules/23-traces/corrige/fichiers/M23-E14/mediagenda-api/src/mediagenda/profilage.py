"""Profilage continu de MédiAgenda (Pyroscope) et lien span → profil.

Activé seulement si MEDIAGENDA_PYROSCOPE_URL est définie (posée par le composant kustomize
« telemetrie » de mediagenda/deploiement) : en local et dans les tests, rien ne démarre.

À appeler une seule fois, dans le processus qui sert les requêtes, APRÈS la configuration des traces
(le fournisseur de traces doit exister pour recevoir le processeur de spans) et avant uvicorn.run.
Le client Pyroscope démarre des fils d'exécution : il n'est pas sûr après un fork (pas de --workers).
"""

from __future__ import annotations

import logging
import os

journal = logging.getLogger("mediagenda")


def _environnement() -> str:
    """deployment.environment.name lu dans OTEL_RESOURCE_ATTRIBUTES (« inconnu » sinon)."""
    for paire in os.environ.get("OTEL_RESOURCE_ATTRIBUTES", "").split(","):
        cle, _, valeur = paire.partition("=")
        if cle.strip() == "deployment.environment.name" and valeur.strip():
            return valeur.strip()
    return "inconnu"


def configurer_profilage(version: str) -> bool:
    """Démarre le profileur CPU et branche le lien traces ↔ profils. Renvoie True s'il tourne."""
    adresse = os.environ.get("MEDIAGENDA_PYROSCOPE_URL", "").strip()
    if not adresse:
        journal.info("profilage désactivé (MEDIAGENDA_PYROSCOPE_URL vide)")
        return False

    import pyroscope
    from opentelemetry import trace
    from pyroscope.otel import PyroscopeSpanProcessor

    pyroscope.configure(
        # Même nom que les traces : c'est la clé du lien Tempo → Pyroscope (étiquette service_name).
        application_name=os.environ.get("OTEL_SERVICE_NAME", "mediagenda-api"),
        server_address=adresse,
        sample_rate=100,  # échantillons par seconde : le surcoût se mesure (E14), il ne se devine pas
        oncpu=True,  # temps CPU seulement : une attente (base, réseau) ne figure PAS dans le profil
        gil_only=True,
        enable_logging=False,
        tags={"version": version, "environnement": _environnement()},
    )
    fournisseur = trace.get_tracer_provider()
    if hasattr(fournisseur, "add_span_processor"):
        # Pose pyroscope.profile.id sur chaque span racine et étiquette les échantillons du même fil.
        fournisseur.add_span_processor(PyroscopeSpanProcessor())
    else:
        journal.warning("fournisseur de traces absent : profils sans lien avec les traces")
    journal.info("profilage démarré", extra={"pyroscope": adresse})
    return True
