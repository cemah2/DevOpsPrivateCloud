"""Point d'entrée : ``python -m mediagenda`` (ou la commande ``mediagenda``).

Lance uvicorn sur 0.0.0.0:$MEDIAGENDA_PORT (8000 par défaut).

Arrêt propre : uvicorn intercepte SIGTERM et SIGINT, cesse d'accepter de
nouvelles connexions, laisse finir les requêtes en cours (au plus
$MEDIAGENDA_DELAI_ARRET secondes), puis exécute la fin du « lifespan »
(fermeture des connexions PostgreSQL et Valkey). Pour que le signal arrive
jusqu'ici, ce processus doit être le PID 1 du conteneur (ou recevoir le signal
de son superviseur) : pas de « sh -c » intermédiaire qui l'avalerait.
"""

from __future__ import annotations

import logging
import sys

import uvicorn

from . import journal
from .app import create_app
from .config import ErreurConfiguration, Settings


def main() -> None:
    try:
        settings = Settings.depuis_env()
    except ErreurConfiguration as exc:
        journal.configurer()
        logging.getLogger("mediagenda").critical("configuration invalide : %s", exc)
        sys.exit(2)
    journal.configurer(settings.log_level, settings.log_format)
    uvicorn.run(
        create_app(settings),
        host="0.0.0.0",  # noqa: S104 - écoute sur toutes les interfaces (conteneur)
        port=settings.port,
        log_config=None,  # on garde notre configuration de journaux (journal.py)
        access_log=False,  # remplacé par la ligne JSON de app.py
        timeout_graceful_shutdown=settings.delai_arret,
    )


if __name__ == "__main__":
    main()
