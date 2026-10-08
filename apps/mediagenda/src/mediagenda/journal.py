"""Journalisation : une ligne JSON par événement, sur la sortie standard.

Le processus n'écrit jamais dans un fichier (facteur XI) : c'est la plateforme
(journald, le moteur de conteneurs, Kubernetes) qui collecte stdout.
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime

# Attributs standard d'un LogRecord : tout ce qui n'est pas dedans a été passé
# par « extra=... » et part tel quel dans la ligne JSON.
# « color_message » : doublon colorisé ajouté par uvicorn, inutile en JSON.
_ATTRIBUTS_STANDARD = set(vars(logging.makeLogRecord({}))) | {
    "message",
    "asctime",
    "taskName",
    "color_message",
}


class FormateurJson(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        ligne = {
            "horodatage": datetime.fromtimestamp(record.created, UTC).isoformat(
                timespec="milliseconds"
            ),
            "niveau": record.levelname,
            "journal": record.name,
            "message": record.getMessage(),
        }
        for cle, valeur in vars(record).items():
            if cle not in _ATTRIBUTS_STANDARD and not cle.startswith("_"):
                ligne[cle] = valeur
        if record.exc_info:
            ligne["exception"] = self.formatException(record.exc_info)
        return json.dumps(ligne, ensure_ascii=False, default=str)


def configurer(niveau: str = "INFO", fmt: str = "json") -> None:
    """Configure la racine des journaux (et ceux d'uvicorn) sur stdout."""
    gestionnaire = logging.StreamHandler(sys.stdout)
    if fmt == "json":
        gestionnaire.setFormatter(FormateurJson())
    else:
        gestionnaire.setFormatter(
            logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
        )
    racine = logging.getLogger()
    racine.handlers[:] = [gestionnaire]
    racine.setLevel(niveau)
    # uvicorn installe ses propres gestionnaires : on les renvoie vers la racine.
    # Son journal d'accès est désactivé, l'application écrit le sien (app.py).
    for nom in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        journal = logging.getLogger(nom)
        journal.handlers.clear()
        journal.propagate = True
