"""Source RabbitMQ (AMQP 0-9-1, client pika en mode bloquant).

Garanties :
- ``prefetch_count=1`` : le courtier ne confie qu'un message à la fois à ce worker ;
- acquittement manuel *après* l'envoi : si le worker meurt en plein traitement,
  le message non acquitté est redistribué (livraison « au moins une fois ») ;
- message invalide : rejeté sans remise en file (``requeue=False``) ; si la file
  a une *dead letter exchange*, il y part, sinon il est supprimé ;
- échec passager : rejeté avec remise en file, après une courte pause ;
- connexion perdue : reconnexion avec attente croissante (1 s, 2 s, 4 s… 30 s).
"""

from __future__ import annotations

import logging
import threading
from collections.abc import Callable
from typing import Any

import pika
import pika.exceptions

from ..traitement import Resultat
from .base import Traitement

journal = logging.getLogger("medinotif.rabbitmq")

ERREURS_CONNEXION = (
    pika.exceptions.AMQPConnectionError,
    pika.exceptions.ConnectionClosedByBroker,
    pika.exceptions.StreamLostError,
    pika.exceptions.ChannelClosedByBroker,
)


class SourceRabbitMQ:
    def __init__(
        self,
        url: str,
        file: str = "notifications",
        type_file: str = "quorum",
        declarer_file: bool = True,
        connecter: Callable[[str], Any] | None = None,
    ) -> None:
        self.url = url
        self.file = file
        self.type_file = type_file
        self.declarer_file = declarer_file
        # Injectable pour les tests (faux courtier).
        self._connecter = connecter or (lambda u: pika.BlockingConnection(pika.URLParameters(u)))
        self._arret = threading.Event()

    def arreter(self) -> None:
        self._arret.set()

    def consommer(self, traiter: Traitement) -> None:
        attente = 1.0
        while not self._arret.is_set():
            try:
                self._session(traiter)
                attente = 1.0
            except ERREURS_CONNEXION as exc:
                journal.warning(
                    "connexion RabbitMQ perdue, nouvelle tentative",
                    extra={"erreur": repr(exc), "attente_s": attente},
                )
                self._arret.wait(attente)
                attente = min(attente * 2, 30.0)
        journal.info("consommation arrêtée")

    def _session(self, traiter: Traitement) -> None:
        connexion = self._connecter(self.url)
        try:
            canal = connexion.channel()
            if self.declarer_file:
                # Déclaration idempotente. Si la file existe déjà avec d'autres
                # arguments, le courtier ferme le canal (PRECONDITION_FAILED) :
                # mettre MEDINOTIF_DECLARER_FILE=0 si la plateforme crée la file.
                canal.queue_declare(
                    queue=self.file, durable=True, arguments={"x-queue-type": self.type_file}
                )
            canal.basic_qos(prefetch_count=1)
            journal.info("consommation démarrée", extra={"file": self.file})
            # inactivity_timeout : rend la main chaque seconde sans message,
            # pour vérifier le drapeau d'arrêt.
            for methode, _proprietes, corps in canal.consume(self.file, inactivity_timeout=1):
                if methode is not None:
                    self._acquitter(canal, methode.delivery_tag, traiter(corps))
                if self._arret.is_set():
                    break
            # Annule l'abonnement ; les messages reçus mais non acquittés
            # retournent dans la file.
            canal.cancel()
        finally:
            if connexion.is_open:
                connexion.close()

    def _acquitter(self, canal: Any, etiquette: int, resultat: Resultat) -> None:
        if resultat is Resultat.ENVOYE:
            canal.basic_ack(delivery_tag=etiquette)
        elif resultat is Resultat.INVALIDE:
            canal.basic_nack(delivery_tag=etiquette, requeue=False)
        else:
            self._arret.wait(1)  # évite de reboucler à pleine vitesse sur un échec
            canal.basic_nack(delivery_tag=etiquette, requeue=True)
