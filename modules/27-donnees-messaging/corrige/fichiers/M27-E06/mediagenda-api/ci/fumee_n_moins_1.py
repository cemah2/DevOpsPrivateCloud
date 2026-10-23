"""Essai de fumée de la version N−1 de l'API contre le schéma de la branche (M27-E06, DEV-2806).

Lancé par le job CI « migrations:compatibilite » DANS l'image publiée de la version en production :
c'est le code N−1 (paquet ``mediagenda`` de l'image) qui s'exécute, contre une base à laquelle on vient
d'appliquer les migrations de la BRANCHE. Si une migration casse la version qui tourne encore (colonne
renommée, NOT NULL sans défaut…), l'une des quatre opérations échoue et le job est rouge.

N'utilise que ce qui existe dans toutes les versions de l'API depuis le M12 : DepotPostgres (créer,
obtenir, lister, supprimer) et RendezVousCreation. Données factices.
Usage : MEDIAGENDA_DB_URL=postgresql://… python ci/fumee_n_moins_1.py
"""

from __future__ import annotations

import os
import sys
from datetime import UTC, datetime, timedelta

from mediagenda.depot import DepotPostgres
from mediagenda.modeles import RendezVousCreation


class EchecFumee(Exception):
    pass


def verifier(condition: bool, message: str) -> None:
    # Pas d'« assert » : python -O les retire, et l'essai ne vérifierait plus rien.
    if not condition:
        raise EchecFumee(message)


def main() -> int:
    depot = DepotPostgres(os.environ["MEDIAGENDA_DB_URL"], taille_max=2)
    try:
        # Créneau unique à chaque exécution (index unique praticien + début, V2).
        debut = datetime.now(UTC).replace(microsecond=0) + timedelta(days=3650)
        cree = depot.creer(
            RendezVousCreation(
                patient="Patient Essai", praticien="dr-fumee", debut=debut, motif="fumée CI"
            )
        )
        relu = depot.obtenir(cree.id)
        verifier(relu is not None and relu.patient == "Patient Essai", "relecture impossible")
        verifier(any(r.id == cree.id for r in depot.lister(limite=1000)), "absent de la liste")
        verifier(depot.supprimer(cree.id) is not None, "suppression impossible")
        print(f"fumée N−1 : OK (rendez-vous {cree.id} créé, relu, listé, supprimé)")
        return 0
    except Exception as exc:  # le job doit afficher la cause, pas seulement une trace
        print(f"fumée N−1 : ÉCHEC — {type(exc).__name__} : {exc}", file=sys.stderr)
        return 1
    finally:
        depot.fermer()


if __name__ == "__main__":
    sys.exit(main())
