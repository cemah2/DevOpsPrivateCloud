"""Schémas d'entrée et de sortie de l'API."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import AwareDatetime, BaseModel, Field


class RendezVousCreation(BaseModel):
    patient: str = Field(min_length=1, max_length=200, description="Nom du patient")
    praticien: str = Field(min_length=1, max_length=100, description="Identifiant du praticien")
    # Une date sans fuseau est refusée (422) : « 2026-11-02T09:00:00+01:00 ».
    debut: AwareDatetime
    duree_minutes: int = Field(default=30, ge=5, le=240)
    motif: str | None = Field(default=None, max_length=500)


class RendezVous(RendezVousCreation):
    id: int
    cree_le: datetime


class Creneaux(BaseModel):
    date: date
    praticien: str
    fuseau: str
    libres: list[datetime]
