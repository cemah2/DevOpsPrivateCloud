"""Cache : interface « Cache » et implémentation Valkey.

Valkey parle le protocole de Redis : on utilise le client Python ``redis``.
"""

from __future__ import annotations

from typing import Protocol

import redis


class Cache(Protocol):
    def ping(self) -> None: ...
    def lire(self, cle: str) -> str | None: ...
    def ecrire(self, cle: str, valeur: str, ttl: int) -> None: ...
    def effacer(self, cle: str) -> None: ...
    def fermer(self) -> None: ...


class CacheValkey:
    def __init__(self, url: str) -> None:
        # Délais courts : un cache lent ne doit pas ralentir l'API.
        self._client = redis.Redis.from_url(
            url, socket_connect_timeout=2, socket_timeout=2, decode_responses=True
        )

    def ping(self) -> None:
        self._client.ping()

    def lire(self, cle: str) -> str | None:
        return self._client.get(cle)

    def ecrire(self, cle: str, valeur: str, ttl: int) -> None:
        self._client.set(cle, valeur, ex=ttl)

    def effacer(self, cle: str) -> None:
        self._client.delete(cle)

    def fermer(self) -> None:
        self._client.close()
