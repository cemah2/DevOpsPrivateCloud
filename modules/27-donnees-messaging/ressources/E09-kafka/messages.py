#!/usr/bin/env python3
"""Génère un lot de demandes de notification de TEST, une par ligne (JSON Lines) — M27-E09, E10.

Même format que ressources/E04-messages/publier.py (RabbitMQ), pour comparer les deux courtiers sur
le MÊME jeu. Données FACTICES uniquement : numéros +336000000xx, adresses @exemple.fr.
Bibliothèque standard seulement (python3 d'adm01) :

    admin@adm01:~$ python3 messages.py --valides 1000 --invalides 10 > ~/m27/e10/lot.jsonl
    admin@adm01:~$ kubectl -n kafka-essai create configmap messages-essai \\
        --from-file=messages.jsonl=$HOME/m27/e10/lot.jsonl --dry-run=client -o yaml | kubectl apply -f -

Les invalides sont répartis dans le lot (un tous les N valides), pas regroupés à la fin.
"""

from __future__ import annotations

import argparse
import json
import sys

PIEGES = [
    "ceci n'est pas du JSON",
    json.dumps({"type": "pigeon", "destinataire": "x", "modele": "m", "rendez_vous_id": 1}),
    json.dumps({"type": "sms", "modele": "rappel-veille", "rendez_vous_id": 2}),
]


def valide(i: int, modele: str) -> str:
    if i % 2 == 0:
        demande = {"type": "sms", "destinataire": f"+336000000{i % 100:02d}"}
    else:
        demande = {"type": "mail", "destinataire": f"essai{i}@exemple.fr"}
    demande |= {"modele": modele, "rendez_vous_id": 900000 + i}
    return json.dumps(demande)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--valides", type=int, default=1000)
    p.add_argument("--invalides", type=int, default=10)
    p.add_argument("--modele", default="essai-m27")
    args = p.parse_args()
    pas = max(1, args.valides // max(1, args.invalides))
    n_inv = 0
    for i in range(args.valides):
        print(valide(i, args.modele))
        if n_inv < args.invalides and (i + 1) % pas == 0:
            print(PIEGES[n_inv % len(PIEGES)])
            n_inv += 1
    while n_inv < args.invalides:
        print(PIEGES[n_inv % len(PIEGES)])
        n_inv += 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
