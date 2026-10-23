#!/usr/bin/env python3
"""Publie des demandes de notification de TEST vers RabbitMQ (M27-E04, M27-E08, M27-E20).

Outil du workbook, à lancer depuis adm01. Il publie N messages VALIDES (au format de MédiNotif) et
M messages INVALIDES sur l'échange « notifications » d'un vhost, en AMQPS, avec confirmations de
publication et « mandatory » : un message non confirmé ou non routé est signalé.

Données FACTICES uniquement : numéros +336000000xx, adresses @exemple.fr.

Le port 5671 de la grappe n'est joignable que dans le cluster : passe par un port-forward, et
l'outil vérifie quand même le certificat SOUS SON VRAI NOM (--nom-tls) :

    admin@adm01:~$ kubectl -n messagerie port-forward svc/rabbitmq 15671:5671 &
    admin@adm01:~$ export AMQP_MOT_DE_PASSE="$(bao kv get -mount=kv -field=mot_de_passe mediagenda/recette/amqp)"
    admin@adm01:~$ uv run --no-project --with 'pika==1.4.4' publier.py --vhost medinotif-recette \\
        --utilisateur mediagenda-recette --valides 10 --invalides 2

Le mot de passe est lu dans la variable AMQP_MOT_DE_PASSE (jamais en argument : visible par ps).
Code de sortie : 0 si tout a été confirmé et routé, 1 sinon.
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import uuid

import pika
import pika.exceptions

RACINE = "/usr/local/share/ca-certificates/medisphere-root-ca.crt"


def messages(valides: int, invalides: int, modele: str) -> list[tuple[str, bytes]]:
    sortie: list[tuple[str, bytes]] = []
    for i in range(valides):
        if i % 2 == 0:
            demande = {"type": "sms", "destinataire": f"+336000000{i % 100:02d}"}
        else:
            demande = {"type": "mail", "destinataire": f"essai{i}@exemple.fr"}
        demande |= {"modele": modele, "rendez_vous_id": 900000 + i}
        sortie.append(("valide", json.dumps(demande).encode()))
    pieges = [
        b"ceci n'est pas du JSON",
        json.dumps({"type": "pigeon", "destinataire": "x", "modele": "m", "rendez_vous_id": 1}).encode(),
        json.dumps({"type": "sms", "modele": "rappel-veille", "rendez_vous_id": 2}).encode(),
    ]
    for i in range(invalides):
        sortie.append(("invalide", pieges[i % len(pieges)]))
    return sortie


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--hote", default="127.0.0.1", help="adresse jointe (port-forward : 127.0.0.1)")
    p.add_argument("--port", type=int, default=15671)
    p.add_argument("--nom-tls", default="rabbitmq.messagerie.svc", help="nom vérifié dans le certificat")
    p.add_argument("--ca", default=RACINE, help="racine de confiance (PEM)")
    p.add_argument("--vhost", required=True)
    p.add_argument("--utilisateur", required=True)
    p.add_argument("--echange", default="notifications")
    p.add_argument("--cle", default="notifications")
    p.add_argument("--modele", default="essai-m27")
    p.add_argument("--valides", type=int, default=10)
    p.add_argument("--invalides", type=int, default=0)
    args = p.parse_args()

    mot_de_passe = os.environ.get("AMQP_MOT_DE_PASSE")
    if not mot_de_passe:
        print("AMQP_MOT_DE_PASSE absente", file=sys.stderr)
        return 2

    contexte = ssl.create_default_context(cafile=args.ca)  # vérifie la chaîne ET le nom
    parametres = pika.ConnectionParameters(
        host=args.hote,
        port=args.port,
        virtual_host=args.vhost,
        credentials=pika.PlainCredentials(args.utilisateur, mot_de_passe),
        ssl_options=pika.SSLOptions(contexte, server_hostname=args.nom_tls),
        connection_attempts=1,
        socket_timeout=5,
        blocked_connection_timeout=10,
    )
    try:
        connexion = pika.BlockingConnection(parametres)
    except (pika.exceptions.AMQPError, OSError) as exc:  # ssl.SSLError est un OSError
        print(f"connexion impossible : {exc!r}", file=sys.stderr)
        return 1

    canal = connexion.channel()
    canal.confirm_delivery()
    bilan = {"confirmes": 0, "refuses": 0, "non_routes": 0}
    for nature, corps in messages(args.valides, args.invalides, args.modele):
        try:
            canal.basic_publish(
                exchange=args.echange,
                routing_key=args.cle,
                body=corps,
                properties=pika.BasicProperties(
                    content_type="application/json",
                    delivery_mode=pika.DeliveryMode.Persistent,
                    message_id=uuid.uuid4().hex,
                    app_id="wb-publier",
                    headers={"essai": nature},
                ),
                mandatory=True,
            )
            bilan["confirmes"] += 1
        except pika.exceptions.UnroutableError:
            bilan["non_routes"] += 1
        except pika.exceptions.NackError:
            bilan["refuses"] += 1
        except pika.exceptions.ChannelClosedByBroker as exc:
            print(f"canal fermé par le courtier : {exc!r}", file=sys.stderr)
            bilan["refuses"] += 1
            break
    if connexion.is_open:
        connexion.close()
    print(json.dumps(bilan))
    return 0 if bilan["refuses"] == 0 and bilan["non_routes"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
