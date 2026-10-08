"""Interface commune des sources de messages."""

from __future__ import annotations

from collections.abc import Callable
from typing import Protocol

from ..traitement import Resultat

Traitement = Callable[[bytes], Resultat]


class Source(Protocol):
    """Une source de messages (RabbitMQ, stdin, plus tard Kafka).

    - ``consommer`` bloque : il lit les messages un par un, appelle
      ``traiter(corps)`` et confirme ou rejette le message selon le résultat,
      jusqu'à ce que ``arreter`` soit appelé ou que la source soit épuisée.
    - ``arreter`` peut être appelé depuis un gestionnaire de signal : il ne fait
      que lever un drapeau. Le message en cours est terminé et confirmé, puis
      ``consommer`` rend la main.
    """

    def consommer(self, traiter: Traitement) -> None: ...
    def arreter(self) -> None: ...
