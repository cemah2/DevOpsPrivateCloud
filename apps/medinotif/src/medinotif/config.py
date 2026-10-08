"""Configuration de MédiNotif, lue uniquement dans les variables d'environnement."""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass

BACKENDS = ("rabbitmq", "stdin", "kafka")
TYPES_FILE = ("quorum", "classic")


class ErreurConfiguration(Exception):
    pass


@dataclass(frozen=True)
class Settings:
    backend: str = "rabbitmq"
    amqp_url: str | None = None
    file: str = "notifications"
    type_file: str = "quorum"
    declarer_file: bool = True
    port_metriques: int = 9100
    log_level: str = "INFO"
    log_format: str = "json"
    delai_envoi_ms: int = 50
    version: str = "dev"

    @classmethod
    def depuis_env(cls, env: Mapping[str, str] | None = None) -> Settings:
        env = os.environ if env is None else env
        backend = env.get("MEDINOTIF_BACKEND", "rabbitmq").lower()
        if backend not in BACKENDS:
            raise ErreurConfiguration(
                f"MEDINOTIF_BACKEND invalide : {backend!r} ({', '.join(BACKENDS)})"
            )
        amqp_url = env.get("MEDINOTIF_AMQP_URL") or None
        if backend == "rabbitmq" and amqp_url is None:
            raise ErreurConfiguration("MEDINOTIF_AMQP_URL obligatoire avec le backend rabbitmq")
        type_file = env.get("MEDINOTIF_TYPE_FILE", "quorum").lower()
        if type_file not in TYPES_FILE:
            raise ErreurConfiguration(
                f"MEDINOTIF_TYPE_FILE invalide : {type_file!r} (quorum ou classic)"
            )
        fmt = env.get("MEDINOTIF_LOG_FORMAT", "json").lower()
        if fmt not in ("json", "texte"):
            raise ErreurConfiguration(f"MEDINOTIF_LOG_FORMAT invalide : {fmt!r} (json ou texte)")
        niveau = env.get("MEDINOTIF_LOG_LEVEL", "INFO").upper()
        if niveau not in ("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"):
            raise ErreurConfiguration(f"MEDINOTIF_LOG_LEVEL invalide : {niveau!r}")
        return cls(
            backend=backend,
            amqp_url=amqp_url,
            file=env.get("MEDINOTIF_FILE", "notifications"),
            type_file=type_file,
            declarer_file=env.get("MEDINOTIF_DECLARER_FILE", "1").lower()
            not in ("0", "non", "false"),
            port_metriques=_entier(env, "MEDINOTIF_PORT_METRIQUES", 9100),
            log_level=niveau,
            log_format=fmt,
            delai_envoi_ms=_entier(env, "MEDINOTIF_DELAI_ENVOI_MS", 50),
            version=env.get("MEDINOTIF_VERSION", "dev"),
        )


def _entier(env: Mapping[str, str], nom: str, defaut: int) -> int:
    brut = env.get(nom)
    if not brut:
        return defaut
    try:
        valeur = int(brut)
    except ValueError as exc:
        raise ErreurConfiguration(f"{nom} doit être un entier : {brut!r}") from exc
    if valeur < 0:
        raise ErreurConfiguration(f"{nom} doit être positif : {brut!r}")
    return valeur
