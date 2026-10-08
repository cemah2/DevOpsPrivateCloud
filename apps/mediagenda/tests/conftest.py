"""Doublures de test : dépôt et cache en mémoire, aucune base réelle."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient

from mediagenda.app import create_app
from mediagenda.config import Settings
from mediagenda.depot import ConflitCreneau
from mediagenda.modeles import RendezVous, RendezVousCreation


class DepotMemoire:
    def __init__(self) -> None:
        self.rdv: dict[int, RendezVous] = {}
        self.suivant = 1
        self.en_panne = False
        self.appels_creneaux = 0
        self.ferme = False

    def ping(self) -> None:
        if self.en_panne:
            raise ConnectionError("PostgreSQL injoignable")

    def lister(self, limite: int = 100) -> list[RendezVous]:
        return sorted(self.rdv.values(), key=lambda r: r.debut)[:limite]

    def obtenir(self, rdv_id: int) -> RendezVous | None:
        return self.rdv.get(rdv_id)

    def creer(self, rdv: RendezVousCreation) -> RendezVous:
        if any(r.praticien == rdv.praticien and r.debut == rdv.debut for r in self.rdv.values()):
            raise ConflitCreneau
        cree = RendezVous(id=self.suivant, cree_le=datetime.now(UTC), **rdv.model_dump())
        self.rdv[cree.id] = cree
        self.suivant += 1
        return cree

    def supprimer(self, rdv_id: int) -> RendezVous | None:
        return self.rdv.pop(rdv_id, None)

    def debuts_occupes(self, praticien, de, a):
        self.appels_creneaux += 1
        return [
            r.debut
            for r in self.rdv.values()
            if (praticien is None or r.praticien == praticien) and de <= r.debut < a
        ]

    def fermer(self) -> None:
        self.ferme = True


class CacheMemoire:
    def __init__(self) -> None:
        self.donnees: dict[str, str] = {}
        self.ttl: dict[str, int] = {}
        self.en_panne = False
        self.ferme = False

    def _verifier(self) -> None:
        if self.en_panne:
            raise ConnectionError("Valkey injoignable")

    def ping(self) -> None:
        self._verifier()

    def lire(self, cle: str) -> str | None:
        self._verifier()
        return self.donnees.get(cle)

    def ecrire(self, cle: str, valeur: str, ttl: int) -> None:
        self._verifier()
        self.donnees[cle] = valeur
        self.ttl[cle] = ttl

    def effacer(self, cle: str) -> None:
        self._verifier()
        self.donnees.pop(cle, None)

    def fermer(self) -> None:
        self.ferme = True


@pytest.fixture
def settings() -> Settings:
    return Settings(db_url="postgresql://test", valkey_url="redis://test", version="1.2.3")


@pytest.fixture
def depot() -> DepotMemoire:
    return DepotMemoire()


@pytest.fixture
def cache() -> CacheMemoire:
    return CacheMemoire()


@pytest.fixture
def client(settings, depot, cache):
    with TestClient(create_app(settings, depot=depot, cache=cache)) as c:
        yield c
