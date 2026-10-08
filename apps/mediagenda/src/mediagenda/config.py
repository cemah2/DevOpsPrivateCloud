"""Configuration de MédiAgenda, lue uniquement dans les variables d'environnement.

Aucun fichier de configuration, aucune valeur secrète par défaut (facteur III
des « 12 facteurs ») : ce qui change d'un environnement à l'autre vient de
l'environnement du processus.
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass

NIVEAUX_JOURNAL = ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")
FORMATS_JOURNAL = ("json", "texte")


class ErreurConfiguration(Exception):
    """Configuration absente ou invalide : le processus doit s'arrêter."""


@dataclass(frozen=True)
class Settings:
    db_url: str
    valkey_url: str
    log_level: str = "INFO"
    log_format: str = "json"
    version: str = "dev"
    port: int = 8000
    fuseau: str = "Europe/Paris"
    cache_ttl: int = 60
    delai_arret: int = 20

    @classmethod
    def depuis_env(cls, env: Mapping[str, str] | None = None) -> Settings:
        """Construit la configuration depuis ``env`` (par défaut ``os.environ``)."""
        env = os.environ if env is None else env
        manquantes = [
            nom for nom in ("MEDIAGENDA_DB_URL", "MEDIAGENDA_VALKEY_URL") if not env.get(nom)
        ]
        if manquantes:
            raise ErreurConfiguration(
                "variable(s) obligatoire(s) absente(s) : " + ", ".join(manquantes)
            )

        niveau = env.get("MEDIAGENDA_LOG_LEVEL", "INFO").upper()
        if niveau not in NIVEAUX_JOURNAL:
            raise ErreurConfiguration(f"MEDIAGENDA_LOG_LEVEL invalide : {niveau!r}")
        fmt = env.get("MEDIAGENDA_LOG_FORMAT", "json").lower()
        if fmt not in FORMATS_JOURNAL:
            raise ErreurConfiguration(f"MEDIAGENDA_LOG_FORMAT invalide : {fmt!r} (json ou texte)")

        return cls(
            db_url=env["MEDIAGENDA_DB_URL"],
            valkey_url=env["MEDIAGENDA_VALKEY_URL"],
            log_level=niveau,
            log_format=fmt,
            version=env.get("MEDIAGENDA_VERSION", "dev"),
            port=_entier(env, "MEDIAGENDA_PORT", 8000),
            fuseau=env.get("MEDIAGENDA_FUSEAU", "Europe/Paris"),
            cache_ttl=_entier(env, "MEDIAGENDA_CACHE_TTL", 60),
            delai_arret=_entier(env, "MEDIAGENDA_DELAI_ARRET", 20),
        )


def _entier(env: Mapping[str, str], nom: str, defaut: int) -> int:
    brut = env.get(nom)
    if brut is None or brut == "":
        return defaut
    try:
        valeur = int(brut)
    except ValueError as exc:
        raise ErreurConfiguration(f"{nom} doit être un entier : {brut!r}") from exc
    if valeur < 0:
        raise ErreurConfiguration(f"{nom} doit être positif : {brut!r}")
    return valeur
