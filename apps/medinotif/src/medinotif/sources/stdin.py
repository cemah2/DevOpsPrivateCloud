"""Source « stdin » : un message JSON par ligne. Pour les tests et le développement.

    $ echo '{"type":"sms","destinataire":"+33612345678","modele":"rappel","rendez_vous_id":1}' \\
        | MEDINOTIF_BACKEND=stdin uv run medinotif

Après un signal d'arrêt, la source s'arrête à la ligne suivante ou à la fin du
flux (une lecture bloquée sur un terminal n'est pas interrompue).
"""

from __future__ import annotations

import logging
import sys
import threading
from typing import TextIO

from .base import Traitement

journal = logging.getLogger("medinotif.stdin")


class SourceStdin:
    def __init__(self, flux: TextIO | None = None) -> None:
        self.flux = flux if flux is not None else sys.stdin
        self._arret = threading.Event()

    def consommer(self, traiter: Traitement) -> None:
        for ligne in self.flux:
            if self._arret.is_set():
                break
            ligne = ligne.strip()
            if ligne:
                resultat = traiter(ligne.encode())
                journal.debug("ligne traitée", extra={"resultat": resultat.value})
        journal.info("fin de la source stdin")

    def arreter(self) -> None:
        self._arret.set()
