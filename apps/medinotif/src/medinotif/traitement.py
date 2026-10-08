"""Traitement d'un message : analyse, envoi (simulé), métriques.

Le traitement ne sait pas d'où vient le message (RabbitMQ, stdin, demain
Kafka) : il reçoit des octets et rend un ``Resultat`` que la source traduit
dans son propre vocabulaire (ack, nack, commit d'offset…).
"""

from __future__ import annotations

import enum
import logging
import time
from typing import Protocol

from prometheus_client import Counter, Histogram

from .message import MessageInvalide, Notification, analyser

journal = logging.getLogger("medinotif")

MESSAGES = Counter(
    "medinotif_messages_total",
    "Messages de notification traités",
    ["type", "resultat"],  # resultat : envoye, invalide, echec
)
DUREE = Histogram(
    "medinotif_traitement_duration_seconds",
    "Durée de traitement d'un message",
)


class Resultat(enum.Enum):
    ENVOYE = "envoye"  # traité : on acquitte
    INVALIDE = "invalide"  # définitivement rejeté : ne pas réessayer
    ECHEC = "echec"  # échec passager : à réessayer


class Expediteur(Protocol):
    def envoyer(self, notification: Notification) -> None: ...


class ExpediteurSimule:
    """N'envoie rien : écrit une ligne de journal à la place du SMS ou du mail."""

    def __init__(self, delai_ms: int = 50) -> None:
        self.delai = delai_ms / 1000

    def envoyer(self, notification: Notification) -> None:
        time.sleep(self.delai)  # simule la latence d'une passerelle SMS / SMTP
        journal.info(
            "notification envoyée (simulation)",
            extra={
                "type": notification.type,
                "destinataire": notification.destinataire_masque(),
                "modele": notification.modele,
                "rendez_vous_id": notification.rendez_vous_id,
            },
        )


class Traiteur:
    def __init__(self, expediteur: Expediteur) -> None:
        self.expediteur = expediteur

    def __call__(self, corps: bytes) -> Resultat:
        with DUREE.time():
            try:
                notification = analyser(corps)
            except MessageInvalide as exc:
                journal.warning("message rejeté", extra={"raison": str(exc)})
                MESSAGES.labels("inconnu", Resultat.INVALIDE.value).inc()
                return Resultat.INVALIDE
            try:
                self.expediteur.envoyer(notification)
            except Exception:
                journal.exception(
                    "échec d'envoi", extra={"rendez_vous_id": notification.rendez_vous_id}
                )
                MESSAGES.labels(notification.type, Resultat.ECHEC.value).inc()
                return Resultat.ECHEC
            MESSAGES.labels(notification.type, Resultat.ENVOYE.value).inc()
            return Resultat.ENVOYE
