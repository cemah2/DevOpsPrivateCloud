"""Client minimal de l'API HTTP de PowerDNS Authoritative 5.0 (M06-E15).

API : http://<serveur>:8081/api/v1/servers/localhost/…, en-tête X-API-Key.
Configuration : le même fichier que le provider OpenTofu de M06-E14,
``~/.config/workbook/powerdns-api.env`` (ou ``MEDICTL_PDNS_ENV_FILE``), mode 600 :
  PDNS_SERVER_URL="http://dns01.par1.medisphere.internal:8081"
  PDNS_API_KEY="…"
Les variables d'environnement du même nom l'emportent (CI).

Le serveur web de PowerDNS ne parle pas TLS : la clé circule en clair entre adm01 et dns01.
C'est un écart accepté jusqu'au durcissement de M06-E30 (mandataire TLS) ; il est limité
par ``webserver-allow-from`` (adm01, runner01) et par le pare-feu.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import requests

from medictl.config import _verifier_droits, lire_fichier_env
from medictl.erreurs import ConfigError, ErreurApi
from medictl.reprises import avec_reprises

log = logging.getLogger(__name__)

FICHIER_DEFAUT = "~/.config/workbook/powerdns-api.env"


@dataclass(frozen=True)
class PdnsConfig:
    url: str
    cle: str = field(repr=False)
    serveur: str = "localhost"


def charger_config_pdns(environ: dict[str, str] | None = None) -> PdnsConfig:
    env = dict(os.environ if environ is None else environ)
    valeurs: dict[str, str] = {}
    chemin = Path(os.path.expanduser(env.get("MEDICTL_PDNS_ENV_FILE", FICHIER_DEFAUT)))
    if chemin.is_file():
        _verifier_droits(chemin)
        valeurs = lire_fichier_env(chemin)
    for cle in ("PDNS_SERVER_URL", "PDNS_API_KEY", "PDNS_SERVER_ID"):
        if env.get(cle):
            valeurs[cle] = env[cle]
    if not valeurs.get("PDNS_SERVER_URL") or not valeurs.get("PDNS_API_KEY"):
        raise ConfigError(f"accès PowerDNS incomplet : PDNS_SERVER_URL et PDNS_API_KEY ({chemin})")
    url = valeurs["PDNS_SERVER_URL"].rstrip("/")
    if not urlsplit(url).hostname:
        raise ConfigError(f"PDNS_SERVER_URL invalide : {url}")
    return PdnsConfig(
        url=url, cle=valeurs["PDNS_API_KEY"], serveur=valeurs.get("PDNS_SERVER_ID") or "localhost"
    )


def traduire_pdns(exc: Exception, operation: str) -> ErreurApi:
    if isinstance(exc, (requests.exceptions.ConnectionError, requests.exceptions.Timeout)):
        return ErreurApi(f"{operation} : API PowerDNS injoignable ({type(exc).__name__})")
    if isinstance(exc, requests.exceptions.HTTPError) and exc.response is not None:
        code = exc.response.status_code
        try:
            detail = exc.response.json().get("error", exc.response.text[:200])
        except ValueError:
            detail = exc.response.text[:200]
        if code == 401:
            return ErreurApi(f"{operation} : clé d'API refusée (401)")
        if code == 403:
            return ErreurApi(f"{operation} : 403, adresse source absente de webserver-allow-from ?")
        return ErreurApi(f"{operation} : HTTP {code} {detail}")
    return ErreurApi(f"{operation} : {exc}")


class ClientPdns:
    def __init__(self, session: requests.Session, url: str, serveur: str = "localhost") -> None:
        self._session = session
        self._base = f"{url}/api/v1/servers/{serveur}/"

    @classmethod
    def depuis_config(cls, cfg: PdnsConfig) -> ClientPdns:
        session = requests.Session()
        session.headers.update({"X-API-Key": cfg.cle, "Accept": "application/json"})
        return cls(session, cfg.url, cfg.serveur)

    def _envoyer(self, methode: str, chemin: str, **kwargs: Any) -> Any:
        reponse = self._session.request(methode, self._base + chemin, timeout=15, **kwargs)
        reponse.raise_for_status()
        return reponse.json() if reponse.content else None

    def zone(self, nom: str) -> dict:
        """Zone complète (rrsets et commentaires). ``nom`` se termine par un point."""
        operation = f"GET zones/{nom}"
        try:
            return avec_reprises(lambda: self._envoyer("GET", f"zones/{nom}"), nom=operation)
        except Exception as exc:
            raise traduire_pdns(exc, operation) from exc

    def modifier_rrsets(self, zone: str, rrsets: list[dict]) -> None:
        """Un seul PATCH par zone : PowerDNS l'applique en une transaction et incrémente le SOA
        (méta-donnée SOA-EDIT-API de la zone)."""
        operation = f"PATCH zones/{zone} ({len(rrsets)} rrset(s))"
        log.info("écriture : %s", operation)
        try:
            self._envoyer("PATCH", f"zones/{zone}", json={"rrsets": rrsets})
        except Exception as exc:
            raise traduire_pdns(exc, operation) from exc
