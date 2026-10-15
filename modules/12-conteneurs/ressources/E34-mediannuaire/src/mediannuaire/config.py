"""Configuration : variables d'environnement uniquement."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


class ErreurConfiguration(Exception):
    """Variable absente ou invalide : le processus s'arrête avec le code 2."""


@dataclass(frozen=True)
class Reglages:
    donnees: Path
    cache_dir: Path
    port: int
    jeton_admin: str
    niveau_journal: str
    version: str
    delai_arret: int

    @classmethod
    def depuis_env(cls, env: dict[str, str] | None = None) -> Reglages:
        env = dict(os.environ if env is None else env)
        jeton = env.get("MEDIANNUAIRE_JETON_ADMIN", "")
        fichier = env.get("MEDIANNUAIRE_JETON_ADMIN_FICHIER", "")
        if fichier:
            try:
                jeton = Path(fichier).read_text(encoding="utf-8").strip()
            except OSError as exc:
                raise ErreurConfiguration(f"MEDIANNUAIRE_JETON_ADMIN_FICHIER illisible : {exc}") from exc
        if len(jeton) < 16:
            raise ErreurConfiguration(
                "jeton d'administration absent ou trop court (MEDIANNUAIRE_JETON_ADMIN "
                "ou MEDIANNUAIRE_JETON_ADMIN_FICHIER, 16 caractères au moins)"
            )
        try:
            port = int(env.get("MEDIANNUAIRE_PORT", "8080"))
            delai = int(env.get("MEDIANNUAIRE_DELAI_ARRET", "10"))
        except ValueError as exc:
            raise ErreurConfiguration(f"valeur numérique invalide : {exc}") from exc
        if not 1 <= port <= 65535:
            raise ErreurConfiguration(f"MEDIANNUAIRE_PORT hors limites : {port}")
        return cls(
            donnees=Path(env.get("MEDIANNUAIRE_DONNEES", "/donnees/praticiens.csv")),
            cache_dir=Path(env.get("MEDIANNUAIRE_CACHE_DIR", "/var/cache/mediannuaire")),
            port=port,
            jeton_admin=jeton,
            niveau_journal=env.get("MEDIANNUAIRE_LOG_LEVEL", "INFO").upper(),
            version=env.get("MEDIANNUAIRE_VERSION", "dev"),
            delai_arret=delai,
        )
