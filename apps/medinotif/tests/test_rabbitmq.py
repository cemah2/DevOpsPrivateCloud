"""Source RabbitMQ testée contre un faux courtier (aucun RabbitMQ réel)."""

from __future__ import annotations

import json
import os
from types import SimpleNamespace

import pika
import pika.exceptions
import pytest

from medinotif.sources import SourceRabbitMQ
from medinotif.traitement import ExpediteurSimule, Resultat, Traiteur

SMS = json.dumps(
    {"type": "sms", "destinataire": "+33612345678", "modele": "rappel", "rendez_vous_id": 1}
).encode()


class FauxCanal:
    def __init__(self, messages):
        self.messages = messages  # liste d'octets ; None = délai d'inactivité
        self.ack, self.nack, self.declarations = [], [], []
        self.annule = False

    def queue_declare(self, queue, durable, arguments):
        self.declarations.append((queue, durable, arguments))

    def basic_qos(self, prefetch_count):
        self.prefetch = prefetch_count

    def consume(self, file, inactivity_timeout):
        for i, corps in enumerate(self.messages, start=1):
            if corps is None:
                yield None, None, None
            else:
                yield SimpleNamespace(delivery_tag=i), None, corps

    def basic_ack(self, delivery_tag):
        self.ack.append(delivery_tag)

    def basic_nack(self, delivery_tag, requeue):
        self.nack.append((delivery_tag, requeue))

    def cancel(self):
        self.annule = True


class FausseConnexion:
    def __init__(self, canal):
        self.canal = canal
        self.is_open = True

    def channel(self):
        return self.canal

    def close(self):
        self.is_open = False


def source_avec(canal, connexions=None):
    connexions = connexions if connexions is not None else []

    def connecter(_url):
        c = FausseConnexion(canal)
        connexions.append(c)
        return c

    return SourceRabbitMQ("amqp://faux", connecter=connecter)


def test_acquittements_selon_le_resultat():
    canal = FauxCanal([SMS, b"invalide", None])
    source = source_avec(canal)
    resultats = iter([Resultat.ENVOYE, Resultat.INVALIDE])

    def traiter(_corps):
        try:
            return next(resultats)
        except StopIteration:
            return Resultat.ENVOYE

    # le faux courtier ne relivre rien : on arrête au premier délai d'inactivité
    canal_consume = canal.consume

    def consume(*a, **k):
        for item in canal_consume(*a, **k):
            if item[0] is None:
                source.arreter()
            yield item

    canal.consume = consume
    source.consommer(traiter)
    assert canal.ack == [1]
    assert canal.nack == [(2, False)]  # invalide : pas de remise en file
    assert canal.declarations == [("notifications", True, {"x-queue-type": "quorum"})]
    assert canal.prefetch == 1
    assert canal.annule


def test_arret_apres_le_message_en_cours():
    canal = FauxCanal([SMS, SMS, SMS])
    connexions = []
    source = source_avec(canal, connexions)
    vus = []

    def traiter(corps):
        vus.append(corps)
        source.arreter()  # SIGTERM pendant le 1er message
        return Resultat.ENVOYE

    source.consommer(traiter)
    assert len(vus) == 1
    assert canal.ack == [1]  # le message en cours est bien acquitté
    assert not connexions[0].is_open


def test_reconnexion_apres_perte_de_connexion(monkeypatch):
    canal = FauxCanal([SMS])
    tentatives = []
    source = SourceRabbitMQ("amqp://faux")

    def connecter(_url):
        tentatives.append(1)
        if len(tentatives) == 1:
            raise pika.exceptions.AMQPConnectionError("refusée")
        return FausseConnexion(canal)

    source._connecter = connecter
    monkeypatch.setattr(source._arret, "wait", lambda _t: None)  # pas d'attente réelle

    def traiter(_corps):
        source.arreter()
        return Resultat.ENVOYE

    source.consommer(traiter)
    assert len(tentatives) == 2
    assert canal.ack == [1]


@pytest.mark.integration
def test_vrai_rabbitmq():
    url = os.environ.get("MEDINOTIF_TEST_AMQP_URL")
    if not url:
        pytest.skip("MEDINOTIF_TEST_AMQP_URL non définie")
    file = "medinotif-test"
    with pika.BlockingConnection(pika.URLParameters(url)) as conn:
        canal = conn.channel()
        canal.queue_declare(queue=file, durable=True, arguments={"x-queue-type": "quorum"})
        canal.basic_publish("", file, SMS)
    source = SourceRabbitMQ(url, file=file)
    traiteur = Traiteur(ExpediteurSimule(0))

    def traiter(corps):
        source.arreter()
        return traiteur(corps)

    source.consommer(traiter)
