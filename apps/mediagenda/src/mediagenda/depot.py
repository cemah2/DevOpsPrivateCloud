"""Accès aux données : interface « Depot » et implémentation PostgreSQL (psycopg 3).

L'API ne connaît que l'interface ``Depot`` : les tests lui passent un dépôt en
mémoire, la production un ``DepotPostgres``.
"""

from __future__ import annotations

from datetime import datetime
from typing import Protocol

from psycopg import errors
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .modeles import RendezVous, RendezVousCreation

# Liste de colonnes constante (jamais une entrée utilisateur) : l'interpolation
# f-string est sans risque ; les valeurs, elles, passent toujours en paramètres.
_COLONNES = "id, patient, praticien, debut, duree_minutes, motif, cree_le"
_INSERTION = f"INSERT INTO rendez_vous (patient, praticien, debut, duree_minutes, motif) VALUES (%s, %s, %s, %s, %s) RETURNING {_COLONNES}"  # noqa: S608


class ConflitCreneau(Exception):
    """Le praticien a déjà un rendez-vous qui commence à cette heure."""


class Depot(Protocol):
    def ping(self) -> None: ...
    def lister(self, limite: int = 100) -> list[RendezVous]: ...
    def obtenir(self, rdv_id: int) -> RendezVous | None: ...
    def creer(self, rdv: RendezVousCreation) -> RendezVous: ...
    def supprimer(self, rdv_id: int) -> RendezVous | None: ...
    def debuts_occupes(
        self, praticien: str | None, de: datetime, a: datetime
    ) -> list[datetime]: ...
    def fermer(self) -> None: ...


class DepotPostgres:
    """Dépôt PostgreSQL avec une réserve (*pool*) de connexions."""

    def __init__(self, url: str, taille_max: int = 10) -> None:
        # open=False puis open(wait=False) : l'application démarre même si la base
        # est indisponible ; c'est /pret qui le signalera (503), pas un plantage.
        self._pool = ConnectionPool(
            url,
            min_size=1,
            max_size=taille_max,
            open=False,
            kwargs={"connect_timeout": 3, "application_name": "mediagenda"},
        )
        self._pool.open(wait=False)

    def ping(self) -> None:
        with self._pool.connection(timeout=2) as conn:
            conn.execute("SELECT 1")

    def lister(self, limite: int = 100) -> list[RendezVous]:
        with self._pool.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"SELECT {_COLONNES} FROM rendez_vous ORDER BY debut LIMIT %s",  # noqa: S608
                (limite,),
            )
            return [RendezVous(**ligne) for ligne in cur.fetchall()]

    def obtenir(self, rdv_id: int) -> RendezVous | None:
        with self._pool.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
            cur.execute(f"SELECT {_COLONNES} FROM rendez_vous WHERE id = %s", (rdv_id,))  # noqa: S608
            ligne = cur.fetchone()
            return RendezVous(**ligne) if ligne else None

    def creer(self, rdv: RendezVousCreation) -> RendezVous:
        try:
            with self._pool.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    _INSERTION,
                    (rdv.patient, rdv.praticien, rdv.debut, rdv.duree_minutes, rdv.motif),
                )
                return RendezVous(**cur.fetchone())
        except errors.UniqueViolation as exc:  # index unique de V2__index.sql
            raise ConflitCreneau from exc

    def supprimer(self, rdv_id: int) -> RendezVous | None:
        with self._pool.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"DELETE FROM rendez_vous WHERE id = %s RETURNING {_COLONNES}",  # noqa: S608
                (rdv_id,),
            )
            ligne = cur.fetchone()
            return RendezVous(**ligne) if ligne else None

    def debuts_occupes(self, praticien: str | None, de: datetime, a: datetime) -> list[datetime]:
        """Débuts des rendez-vous entre ``de`` et ``a`` ; tous praticiens si ``None``."""
        with self._pool.connection() as conn:
            lignes = conn.execute(
                "SELECT debut FROM rendez_vous"
                " WHERE (%(p)s::text IS NULL OR praticien = %(p)s) AND debut >= %(de)s AND debut < %(a)s",
                {"p": praticien, "de": de, "a": a},
            ).fetchall()
            return [ligne[0] for ligne in lignes]

    def fermer(self) -> None:
        self._pool.close()
