"""Journalisation de medictl (M02-E17).

- Tout le journal part sur stderr ; stdout ne porte que les données
  (``medictl vm list -f json | jq`` doit marcher même avec ``-vv``).
- Niveau : WARNING par défaut, INFO avec ``-v``, DEBUG avec ``-vv`` ;
  ``-vvv`` ouvre aussi les journaux de proxmoxer et d'urllib3 (requêtes HTTP).
- Un filtre masque les secrets connus dans TOUS les messages, y compris ceux
  des bibliothèques : défense en profondeur si quelqu'un journalise un en-tête.
"""

from __future__ import annotations

import logging
import sys

FORMAT = "%(asctime)s %(levelname)s %(name)s : %(message)s"
FORMAT_DATE = "%Y-%m-%dT%H:%M:%S%z"


class MasqueSecrets(logging.Filter):
    """Remplace chaque secret enregistré par ``****`` dans le message final."""

    def __init__(self) -> None:
        super().__init__()
        self.secrets: set[str] = set()

    def filter(self, record: logging.LogRecord) -> bool:
        if self.secrets:
            message = record.getMessage()
            for secret in self.secrets:
                message = message.replace(secret, "****")
            record.msg, record.args = message, None
        return True


_masque = MasqueSecrets()


def masquer(secret: str) -> None:
    """Enregistre un secret à ne jamais laisser apparaître dans le journal."""
    if secret:
        _masque.secrets.add(secret)


def configurer_journal(verbosite: int) -> None:
    niveau = {0: logging.WARNING, 1: logging.INFO}.get(verbosite, logging.DEBUG)
    gestionnaire = logging.StreamHandler(sys.stderr)
    gestionnaire.setFormatter(logging.Formatter(FORMAT, FORMAT_DATE))
    gestionnaire.addFilter(_masque)

    racine = logging.getLogger()
    racine.handlers = [gestionnaire]
    racine.setLevel(logging.WARNING)
    logging.getLogger("medictl").setLevel(niveau)
    # proxmoxer fixe ses journaux à WARNING à l'import ; on ne les ouvre qu'à -vvv.
    bavards = logging.DEBUG if verbosite >= 3 else logging.WARNING
    for nom in ("proxmoxer", "proxmoxer.core", "proxmoxer.backends.https", "urllib3"):
        logging.getLogger(nom).setLevel(bavards)
