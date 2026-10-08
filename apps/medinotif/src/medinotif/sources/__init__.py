"""Sources de messages et fabrique.

Ajouter un backend (Kafka au module 27) : écrire une classe qui respecte
l'interface ``Source`` de ``base.py`` (``consommer(traiter)`` et ``arreter()``),
traduire ``Resultat`` dans le vocabulaire du courtier (pour Kafka : valider
l'offset après ENVOYE ou INVALIDE, ne pas le valider après ECHEC), puis
l'ajouter à ``creer_source``. Le traitement (``traitement.py``) ne change pas.
"""

from __future__ import annotations

from ..config import ErreurConfiguration, Settings
from .base import Source, Traitement
from .rabbitmq import SourceRabbitMQ
from .stdin import SourceStdin

__all__ = ["Source", "SourceRabbitMQ", "SourceStdin", "Traitement", "creer_source"]


def creer_source(settings: Settings) -> Source:
    if settings.backend == "stdin":
        return SourceStdin()
    if settings.backend == "rabbitmq":
        if not settings.amqp_url:
            raise ErreurConfiguration("MEDINOTIF_AMQP_URL obligatoire avec le backend rabbitmq")
        return SourceRabbitMQ(
            settings.amqp_url,
            file=settings.file,
            type_file=settings.type_file,
            declarer_file=settings.declarer_file,
        )
    if settings.backend == "kafka":
        raise ErreurConfiguration("backend kafka pas encore disponible (prévu au module 27)")
    raise ErreurConfiguration(f"backend inconnu : {settings.backend}")
