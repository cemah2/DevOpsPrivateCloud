"""Calculs de créneaux de rendez-vous, volontairement simples (exercices de CI du M19)."""

from __future__ import annotations


def creneaux_libres(debut: int, fin: int, duree: int, occupes: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Créneaux de ``duree`` minutes entre ``debut`` et ``fin`` (minutes depuis minuit)
    qui ne chevauchent aucun intervalle de ``occupes``."""
    if duree <= 0:
        raise ValueError("la durée d'un créneau doit être positive")
    if fin <= debut:
        raise ValueError("la fin doit être après le début")
    resultat = []
    t = debut
    while t + duree <= fin:
        candidat = (t, t + duree)
        if all(candidat[1] <= o[0] or candidat[0] >= o[1] for o in occupes):
            resultat.append(candidat)
        t += duree
    return resultat


def duree_totale(creneaux: list[tuple[int, int]]) -> int:
    """Somme des durées des créneaux, en minutes."""
    return sum(fin - debut for debut, fin in creneaux)
