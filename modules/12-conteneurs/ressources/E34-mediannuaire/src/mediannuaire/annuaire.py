"""Chargement de l'annuaire depuis un fichier CSV, avec un index mis en cache sur disque."""

from __future__ import annotations

import csv
import hashlib
import json
import logging
import os
import tempfile
import threading
from pathlib import Path

journal = logging.getLogger("mediannuaire.annuaire")
COLONNES = ("id", "nom", "prenom", "specialite", "cabinet", "ville", "rpps")


class ErreurDonnees(Exception):
    """Fichier de données absent, illisible ou mal formé."""


class Annuaire:
    """Annuaire en mémoire, rechargeable à chaud.

    Au chargement, un index (praticiens groupés par spécialité) est écrit dans le dossier de
    cache, sous le nom de l'empreinte du fichier source : un redémarrage avec les mêmes
    données relit l'index au lieu de le recalculer. Le dossier de cache DOIT être inscriptible.
    """

    def __init__(self, source: Path, cache_dir: Path) -> None:
        self.source = source
        self.cache_dir = cache_dir
        self._verrou = threading.Lock()
        self._praticiens: dict[str, dict[str, str]] = {}
        self._par_specialite: dict[str, list[str]] = {}
        self.empreinte = ""

    @property
    def pret(self) -> bool:
        return bool(self._praticiens)

    def charger(self) -> int:
        try:
            brut = self.source.read_bytes()
        except OSError as exc:
            raise ErreurDonnees(f"fichier de données illisible : {self.source} ({exc.strerror})") from exc
        empreinte = hashlib.sha256(brut).hexdigest()[:16]
        lignes = list(csv.DictReader(brut.decode("utf-8").splitlines(), delimiter=";"))
        if not lignes or tuple(lignes[0].keys()) != COLONNES:
            raise ErreurDonnees(f"en-tête attendu : {';'.join(COLONNES)}")
        praticiens = {ligne["id"]: dict(ligne) for ligne in lignes}
        index = self._index(empreinte, praticiens)
        with self._verrou:
            self._praticiens, self._par_specialite, self.empreinte = praticiens, index, empreinte
        journal.info("annuaire chargé", extra={"praticiens": len(praticiens), "empreinte": empreinte})
        return len(praticiens)

    def _index(self, empreinte: str, praticiens: dict[str, dict[str, str]]) -> dict[str, list[str]]:
        chemin = self.cache_dir / f"index-{empreinte}.json"
        if chemin.exists():
            journal.info("index relu depuis le cache", extra={"chemin": str(chemin)})
            return json.loads(chemin.read_text(encoding="utf-8"))
        index: dict[str, list[str]] = {}
        for pid, p in sorted(praticiens.items()):
            index.setdefault(p["specialite"].lower(), []).append(pid)
        # Écriture atomique : fichier temporaire dans le même dossier, puis renommage.
        # Une erreur ici (dossier absent ou en lecture seule) empêche le démarrage : c'est voulu,
        # l'équipe veut que le cache fonctionne en production (temps de démarrage).
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=self.cache_dir, prefix=".index-")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(index, f, ensure_ascii=False)
        os.replace(tmp, chemin)
        journal.info("index écrit dans le cache", extra={"chemin": str(chemin)})
        return index

    def liste(self, specialite: str | None = None) -> list[dict[str, str]]:
        with self._verrou:
            if specialite:
                ids = self._par_specialite.get(specialite.lower(), [])
                return [self._praticiens[i] for i in ids]
            return [self._praticiens[i] for i in sorted(self._praticiens)]

    def detail(self, pid: str) -> dict[str, str] | None:
        with self._verrou:
            return self._praticiens.get(pid)
