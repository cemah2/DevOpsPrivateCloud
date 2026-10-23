#!/usr/bin/env python3
"""capacite.py — bilan de capacité des budgets d'équipe (plateforme/equipes, F2-S02, PLAT-3202).

    uv run outils/capacite.py            # tableau Markdown sur la sortie standard, code 1 si dépassement

Compare la somme des budgets des équipes ACTIVES ayant un locataire (spec.kubernetes.budget, c'est-à-dire
le plafond de requests que Capsule leur accorde sur tous leurs espaces) à ce qui reste allouable sur les
travailleurs, d'après config/plateforme.yaml (section capacite, relevée à la main par la Plateforme :
docs/accueil/capacite.md). Un budget n'est pas une réservation : c'est une PROMESSE. Le ratio d'engagement
dit combien de promesses on accepte au-delà du reste réel (CPU compressible : un peu plus ; mémoire : non).

Aucun accès au cluster : le relevé est un fait daté, relu en MR. Codes : 0 conforme ; 1 dépassement ou
données invalides.
"""

from __future__ import annotations

import sys
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from rendre import RACINE, Invalide, charger, normaliser, quantite

RESSOURCES = ("requests.cpu", "requests.memory")


def lisible(ressource: str, valeur: Decimal) -> str:
    if ressource == "requests.cpu":
        return f"{valeur:.2f} CPU"
    return f"{valeur / Decimal(1024) ** 3:.2f} Gi"


def main() -> int:
    try:
        config, brutes = charger(RACINE)
        equipes = [normaliser(d) for d in brutes]
    except (OSError, Invalide) as err:
        print(f"capacite : {err}", file=sys.stderr)
        return 1
    c = config["capacite"]
    ratio = {r: Decimal(str(c["ratio_engagement_max"][r])) for r in RESSOURCES}
    print(f"## Bilan de capacité des équipes (relevé du {c['releve']})\n")
    print("| Ressource | Allouable | Déjà réservé | Réserve N-1 | Reste | Plafond d'engagement | Budgets des équipes | Verdict |")
    print("|---|---|---|---|---|---|---|---|")
    depassement = False
    for r in RESSOURCES:
        allouable = quantite(c["allouable"][r])
        reserve = quantite(c["deja_reserve"][r])
        n1 = quantite(c["reserve_perte_noeud"][r])
        reste = allouable - reserve - n1
        plafond = reste * ratio[r]
        budgets = sum((quantite(e["budget"][r]) for e in equipes if e["etat"] == "active" and e["kubernetes"]), Decimal(0))
        ok = budgets <= plafond
        depassement |= not ok
        print(
            f"| {r} | {lisible(r, allouable)} | {lisible(r, reserve)} | {lisible(r, n1)} | {lisible(r, reste)} "
            f"| {lisible(r, plafond)} (× {ratio[r]}) | {lisible(r, budgets)} | {'OK' if ok else '**DÉPASSEMENT**'} |"
        )
    print("\n| Équipe | " + " | ".join(RESSOURCES) + " |")
    print("|---|" + "---|" * len(RESSOURCES))
    for e in equipes:
        if e["etat"] == "active" and e["kubernetes"]:
            print(f"| {e['nom']} | " + " | ".join(lisible(r, quantite(e["budget"][r])) for r in RESSOURCES) + " |")
    if depassement:
        print(
            "\ncapacite : les budgets promis dépassent ce que les travailleurs peuvent tenir : réduire un budget, "
            "ajouter de la capacité (ADR), ou changer le ratio d'engagement (décision écrite).",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
