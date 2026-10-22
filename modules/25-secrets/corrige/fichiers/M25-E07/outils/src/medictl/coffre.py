"""Secrets de medictl lus dans OpenBao (M25-E07, promesse du M02-E19).

medictl s'authentifie comme une MACHINE (méthode AppRole, rôle « medictl ») et lit ses secrets
dans le moteur KV v2 « kv » sous plateforme/medictl/. Les accès viennent d'un fichier en 600
(``MEDICTL_BAO_ENV_FILE``, défaut ``~/.config/workbook/medictl-openbao.env``), lu sans être
exécuté :

    BAO_ADDR=https://openbao.par1.medisphere.internal:8200
    MEDICTL_BAO_ROLE_ID=<role_id du rôle medictl>
    MEDICTL_BAO_SECRET_ID=<secret_id émis pour adm01>

Les variables d'environnement du même nom l'emportent sur le fichier (CI, essais).
Règles : le jeton obtenu (batch, 5 minutes) et les secrets lus ne vivent qu'en mémoire ; ils
n'apparaissent ni dans ``repr()``, ni dans les journaux, ni dans les messages d'erreur ; TLS
toujours vérifié (magasin du système, ou ``BAO_CACERT``).
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import quote, urlsplit

import requests

from medictl.erreurs import ConfigError, ErreurMedictl

FICHIER_DEFAUT = "~/.config/workbook/medictl-openbao.env"
ADRESSE_DEFAUT = "https://openbao.par1.medisphere.internal:8200"
MONTAGE = "kv"
DELAI = 10  # secondes, pour chaque appel


class ErreurCoffre(ErreurMedictl):
    """OpenBao injoignable, identité refusée, secret absent ou illisible."""


@dataclass(frozen=True)
class AccesCoffre:
    adresse: str
    role_id: str
    secret_id: str = field(repr=False)
    cacert: str | None = None

    @property
    def verification_tls(self) -> str | bool:
        if self.cacert:
            return self.cacert
        magasin = "/etc/ssl/certs/ca-certificates.crt"
        return magasin if os.path.isfile(magasin) else True


def charger_acces(environ: dict[str, str] | None = None) -> AccesCoffre | None:
    """Accès au coffre, ou None si medictl n'est pas configuré pour OpenBao."""
    # Import local : config importe ce module (pas d'import circulaire au chargement).
    from medictl.config import _verifier_droits, lire_fichier_env

    env = dict(os.environ if environ is None else environ)
    chemin = Path(os.path.expanduser(env.get("MEDICTL_BAO_ENV_FILE", FICHIER_DEFAUT)))
    valeurs: dict[str, str] = {}
    if chemin.is_file():
        _verifier_droits(chemin)
        valeurs.update(lire_fichier_env(chemin))
    for cle in ("BAO_ADDR", "BAO_CACERT", "MEDICTL_BAO_ROLE_ID", "MEDICTL_BAO_SECRET_ID"):
        if env.get(cle):
            valeurs[cle] = env[cle]

    if not valeurs.get("MEDICTL_BAO_ROLE_ID") and not valeurs.get("MEDICTL_BAO_SECRET_ID"):
        return None
    manquantes = [c for c in ("MEDICTL_BAO_ROLE_ID", "MEDICTL_BAO_SECRET_ID") if not valeurs.get(c)]
    if manquantes:
        raise ConfigError(f"accès OpenBao incomplets, manque : {', '.join(manquantes)} ({chemin})")
    adresse = valeurs.get("BAO_ADDR", ADRESSE_DEFAUT).rstrip("/")
    if urlsplit(adresse).scheme != "https":
        raise ConfigError("BAO_ADDR doit être une URL https:// (TLS obligatoire)")
    return AccesCoffre(
        adresse=adresse,
        role_id=valeurs["MEDICTL_BAO_ROLE_ID"],
        secret_id=valeurs["MEDICTL_BAO_SECRET_ID"],
        cacert=valeurs.get("BAO_CACERT") or None,
    )


class Coffre:
    """Client minimal : connexion AppRole puis lecture KV v2. Un jeton par instance."""

    def __init__(self, acces: AccesCoffre, session: requests.Session | None = None) -> None:
        self._acces = acces
        self._session = session or requests.Session()
        self._jeton: str | None = None

    def __repr__(self) -> str:
        return f"Coffre(adresse={self._acces.adresse!r})"

    def _appel(self, methode: str, chemin: str, **kwargs) -> dict:
        url = f"{self._acces.adresse}/v1/{chemin}"
        try:
            reponse = self._session.request(
                methode, url, timeout=DELAI, verify=self._acces.verification_tls, **kwargs
            )
        except requests.RequestException as exc:
            # Le message de requests ne contient ni corps ni en-têtes : pas de secret dedans.
            raise ErreurCoffre(f"OpenBao injoignable ({self._acces.adresse}) : {exc}") from None
        if reponse.status_code >= 400:
            try:
                # OpenBao renvoie « 1 error occurred:\n\t* permission denied » : une ligne.
                erreurs = "; ".join(
                    " ".join(str(e).split()) for e in reponse.json().get("errors", [])
                )
                erreurs = erreurs or reponse.reason
            except ValueError:
                erreurs = reponse.reason
            raise ErreurCoffre(
                f"OpenBao refuse {methode} /v1/{chemin} ({reponse.status_code}) : {erreurs}"
            )
        return reponse.json()

    def _connexion(self) -> str:
        if self._jeton is None:
            donnees = self._appel(
                "POST",
                "auth/approle/login",
                json={"role_id": self._acces.role_id, "secret_id": self._acces.secret_id},
            )
            jeton = (donnees.get("auth") or {}).get("client_token")
            if not jeton:
                raise ErreurCoffre("connexion AppRole sans jeton dans la réponse")
            self._jeton = jeton
        return self._jeton

    def lire(self, chemin: str, champ: str) -> str:
        """Valeur du champ ``champ`` du secret ``kv/<chemin>`` (dernière version)."""
        donnees = self._appel(
            "GET",
            f"{MONTAGE}/data/{quote(chemin)}",
            headers={"X-Vault-Token": self._connexion()},
        )
        valeur = ((donnees.get("data") or {}).get("data") or {}).get(champ)
        if not isinstance(valeur, str) or not valeur:
            raise ErreurCoffre(f"champ « {champ} » absent ou vide dans {MONTAGE}/{chemin}")
        return valeur
