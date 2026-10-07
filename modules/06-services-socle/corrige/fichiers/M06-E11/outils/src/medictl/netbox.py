"""Client minimal de l'API REST de NetBox 4.6 (M06-E11).

Une seule classe parle à NetBox : ClientNetbox. Comme ClientPVE (M02), elle traduit
toute erreur technique en ErreurApi au message actionnable, et seule la lecture (GET)
est reprise automatiquement.

Authentification : jeton **v2** uniquement (``Authorization: Bearer nbt_<clé>.<jeton>``).
Un jeton v1 (40 caractères hexadécimaux, en-tête ``Token``) est refusé dès le chargement :
ils sont dépréciés en 4.6 et disparaissent en 5.0.

Configuration, du plus faible au plus fort :
1. ``~/.config/workbook/netbox-auto.token`` (ou ``MEDICTL_NETBOX_TOKEN_FILE``), mode 600 ;
2. variables d'environnement ``NETBOX_URL``, ``NETBOX_TOKEN`` (CI : variables protégées
   et masquées), ``NETBOX_CACERT``.
TLS toujours vérifié : ``NETBOX_CACERT`` si défini, sinon le magasin du système, qui
contient la racine « MédiSphère Root CA » depuis M06-E03.
"""

from __future__ import annotations

import logging
import os
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import requests

from medictl.config import MAGASIN_SYSTEME, _verifier_droits
from medictl.erreurs import ConfigError, ErreurApi
from medictl.reprises import avec_reprises

log = logging.getLogger(__name__)

URL_DEFAUT = "https://nbx01.par1.medisphere.internal"
FICHIER_JETON_DEFAUT = "~/.config/workbook/netbox-auto.token"
TAILLE_PAGE = 200


@dataclass(frozen=True)
class NetboxConfig:
    url: str
    jeton: str = field(repr=False)
    cacert: str | None = None

    @property
    def verification_tls(self) -> str | bool:
        """Valeur passée à requests (``verify``) : un chemin d'autorité, ou True. Jamais False."""
        if self.cacert:
            return self.cacert
        return MAGASIN_SYSTEME if os.path.isfile(MAGASIN_SYSTEME) else True


def charger_config_netbox(environ: dict[str, str] | None = None) -> NetboxConfig:
    """Assemble et valide la configuration d'accès à NetBox."""
    env = dict(os.environ if environ is None else environ)
    url = env.get("NETBOX_URL", URL_DEFAUT).rstrip("/")
    morceaux = urlsplit(url)
    if morceaux.scheme != "https" or not morceaux.hostname:
        raise ConfigError("NETBOX_URL doit être une URL https:// (TLS obligatoire)")
    if morceaux.path not in ("", "/"):
        raise ConfigError(
            "NETBOX_URL est l'URL racine de NetBox, sans /api (ex. " + URL_DEFAUT + ")"
        )

    jeton = env.get("NETBOX_TOKEN", "").strip()
    if not jeton:
        chemin = Path(
            os.path.expanduser(env.get("MEDICTL_NETBOX_TOKEN_FILE", FICHIER_JETON_DEFAUT))
        )
        if not chemin.is_file():
            raise ConfigError(f"jeton NetBox introuvable : {chemin} (ou variable NETBOX_TOKEN)")
        _verifier_droits(chemin)
        jeton = chemin.read_text(encoding="utf-8").strip()
    if not jeton.startswith("nbt_") or "." not in jeton:
        raise ConfigError(
            "jeton NetBox au mauvais format : un jeton v2 s'écrit nbt_<clé>.<jeton> "
            "(les jetons v1 sont refusés)"
        )

    cacert = env.get("NETBOX_CACERT") or None
    if cacert and not os.access(cacert, os.R_OK):
        raise ConfigError(f"certificat d'autorité illisible : {cacert} (NETBOX_CACERT)")
    return NetboxConfig(url=url, jeton=jeton, cacert=cacert)


def traduire_netbox(exc: Exception, operation: str) -> ErreurApi:
    """Transforme une exception technique en message utile à l'astreinte."""
    if isinstance(exc, requests.exceptions.SSLError):
        return ErreurApi(
            f"{operation} : certificat de NetBox refusé. La racine MédiSphère est-elle dans "
            "le magasin du système (M06-E03) ? Sinon, NETBOX_CACERT"
        )
    if isinstance(exc, (requests.exceptions.ConnectionError, requests.exceptions.Timeout)):
        return ErreurApi(f"{operation} : NetBox injoignable ({type(exc).__name__})")
    if isinstance(exc, requests.exceptions.HTTPError) and exc.response is not None:
        code = exc.response.status_code
        try:
            detail = exc.response.json()
        except ValueError:
            detail = exc.response.text[:200]
        if code == 401:
            return ErreurApi(f"{operation} : jeton refusé (401) — {detail}")
        if code == 403:
            return ErreurApi(
                f"{operation} : droits insuffisants (403). Jeton en lecture seule, "
                f"adresse source hors des « allowed IPs », ou permission manquante — {detail}"
            )
        return ErreurApi(f"{operation} : HTTP {code} {detail}")
    return ErreurApi(f"{operation} : {exc}")


class ClientNetbox:
    """Accès à /api/ de NetBox. Les chemins sont relatifs à /api/ (ex. « dcim/sites/ »)."""

    def __init__(
        self,
        session: requests.Session,
        base: str,
        *,
        verification: str | bool = True,
        timeout: float = 15,
    ) -> None:
        self._session = session
        self._base = base.rstrip("/") + "/api/"
        self._verification = verification
        self._timeout = timeout

    @classmethod
    def depuis_config(cls, cfg: NetboxConfig) -> ClientNetbox:
        session = requests.Session()
        session.headers.update(
            {
                "Authorization": f"Bearer {cfg.jeton}",
                "Accept": "application/json",
                "User-Agent": "medictl (plateforme/outils)",
            }
        )
        return cls(session, cfg.url, verification=cfg.verification_tls)

    # --- plomberie -------------------------------------------------------------------
    def _url(self, chemin: str) -> str:
        if chemin.startswith("https://"):
            return chemin  # lien « next » renvoyé par NetBox
        return self._base + chemin.lstrip("/")

    def _envoyer(self, methode: str, chemin: str, **kwargs: Any) -> Any:
        reponse = self._session.request(
            methode, self._url(chemin), verify=self._verification, timeout=self._timeout, **kwargs
        )
        reponse.raise_for_status()
        return reponse.json() if reponse.content else None

    def _lire(self, chemin: str, params: dict[str, Any] | None = None) -> Any:
        operation = f"GET {chemin}"
        log.debug("lecture : %s %s", operation, params or "")
        try:
            return avec_reprises(lambda: self._envoyer("GET", chemin, params=params), nom=operation)
        except Exception as exc:
            raise traduire_netbox(exc, operation) from exc

    def _ecrire(self, methode: str, chemin: str, donnees: dict[str, Any]) -> Any:
        operation = f"{methode} {chemin}"
        log.info("écriture : %s", operation)
        try:
            return self._envoyer(methode, chemin, json=donnees)
        except Exception as exc:
            raise traduire_netbox(exc, operation) from exc

    # --- lectures ----------------------------------------------------------------------
    def lister(self, chemin: str, **filtres: Any) -> list[dict]:
        """Tous les objets d'une liste, en suivant la pagination (« next »)."""
        return list(self._parcourir(chemin, filtres))

    def _parcourir(self, chemin: str, filtres: dict[str, Any]) -> Iterator[dict]:
        page = self._lire(chemin, {"limit": TAILLE_PAGE, **filtres})
        while True:
            yield from page.get("results", [])
            suivant = page.get("next")
            if not suivant:
                return
            if not suivant.startswith(self._base):
                # NetBox construit « next » à partir de l'en-tête Host : derrière un mandataire
                # mal réglé, il pointe ailleurs. On refuse de suivre (le jeton partirait avec).
                raise ErreurApi(f"pagination : lien « next » inattendu ({suivant})")
            page = self._lire(suivant)

    def unique(self, chemin: str, **filtres: Any) -> dict | None:
        """L'objet qui correspond aux filtres ; None s'il n'y en a pas ; erreur si plusieurs."""
        resultats = self.lister(chemin, **filtres)
        if len(resultats) > 1:
            raise ErreurApi(f"{chemin} {filtres} : {len(resultats)} objets au lieu d'un")
        return resultats[0] if resultats else None

    def qui_suis_je(self) -> dict:
        """Utilisateur du jeton (/api/authentication-check/, NetBox ≥ 4.5)."""
        return self._lire("authentication-check/")

    # --- écritures (jamais reprises) -----------------------------------------------------
    def creer(self, chemin: str, donnees: dict[str, Any]) -> dict:
        return self._ecrire("POST", chemin, donnees)

    def modifier(self, chemin: str, ident: int, donnees: dict[str, Any]) -> dict:
        return self._ecrire("PATCH", f"{chemin.rstrip('/')}/{ident}/", donnees)
