"""Point d'entrée : ``python -m medinotif`` (ou la commande ``medinotif``).

Arrêt propre : SIGTERM (ou SIGINT) lève le drapeau d'arrêt de la source. Le
message en cours est terminé et acquitté, puis le processus sort avec le code 0.
Le délai de grâce de la plateforme (``terminationGracePeriodSeconds`` sous
Kubernetes, ``TimeoutStopSec`` sous systemd) doit couvrir un traitement.
"""

from __future__ import annotations

import logging
import signal
import sys
from types import FrameType

from prometheus_client import start_http_server

from . import journal as journalisation
from .config import ErreurConfiguration, Settings
from .sources import creer_source
from .traitement import ExpediteurSimule, Traiteur

journal = logging.getLogger("medinotif")


def main() -> None:
    try:
        settings = Settings.depuis_env()
        journalisation.configurer(settings.log_level, settings.log_format)
        source = creer_source(settings)
    except ErreurConfiguration as exc:
        journalisation.configurer()
        journal.critical("configuration invalide : %s", exc)
        sys.exit(2)

    def sur_signal(signum: int, _frame: FrameType | None) -> None:
        journal.info("signal reçu, arrêt après le message en cours", extra={"signal": signum})
        source.arreter()

    signal.signal(signal.SIGTERM, sur_signal)
    signal.signal(signal.SIGINT, sur_signal)

    # /metrics (et n'importe quel chemin) sur le port 9100 : sert aussi de sonde de vivacité.
    start_http_server(settings.port_metriques)
    journal.info(
        "démarrage",
        extra={
            "version": settings.version,
            "backend": settings.backend,
            "port_metriques": settings.port_metriques,
        },
    )
    source.consommer(Traiteur(ExpediteurSimule(settings.delai_envoi_ms)))
    journal.info("arrêt terminé")


if __name__ == "__main__":
    main()
