"""Journalisation : une ligne JSON par événement, sur la sortie standard."""

from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime

# Tout attribut qui n'est pas standard a été passé par « extra=... » et part
# tel quel dans la ligne JSON.
_ATTRIBUTS_STANDARD = set(vars(logging.makeLogRecord({}))) | {"message", "asctime", "taskName"}


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
    # pika est très bavard au niveau INFO (chaque ouverture de canal).
    logging.getLogger("pika").setLevel(max(logging.WARNING, racine.level))
