"""Chiffrement de champs par le moteur transit d'OpenBao (M25-E17, SEC-2617).

La clé ne quitte jamais OpenBao : on lui envoie le clair (en base64), il renvoie un chiffré de la
forme « vault:v<N>:<base64> » ; N est la version de la clé qui a chiffré. Déchiffrer, rechiffrer
(rewrap : passer à la dernière version sans jamais revoir le clair) sont aussi des appels d'API.

Une seule classe parle au réseau : ClientTransit. Les fonctions de champs (chiffrer_champs…)
manipulent des structures JSON et se testent sans OpenBao.

Identité : le JETON de la session. BAO_TOKEN s'il est défini (AppRole de medictl, M25-E07), sinon
~/.vault-token, que « bao login -method=oidc » écrit pour une personne. Adresse : BAO_ADDR.
Autorité : BAO_CACERT si défini, sinon le magasin du système (racine MédiSphère installée sur
adm01, M06) ; jamais verify=False.
"""

from __future__ import annotations

import base64
import logging
import os
import re
from collections.abc import Callable, Iterable
from pathlib import Path
from typing import Any

import requests

from medictl.erreurs import ConfigError, ErreurApi

__all__ = [
    "MOTIF_CHIFFRE",
    "ClientTransit",
    "chiffrer_champs",
    "dechiffrer_champs",
    "rechiffrer_champs",
    "version_du_chiffre",
]

log = logging.getLogger(__name__)

# « vault:v12:… » : préfixe historique conservé par OpenBao (compatibilité avec les clients Vault).
MOTIF_CHIFFRE = re.compile(r"^vault:v(?P<version>[0-9]+):[A-Za-z0-9+/=]+$")
TAILLE_LOT = 100  # éléments par requête batch_input : une requête par lot, pas une par champ


def version_du_chiffre(chiffre: str) -> int:
    """Version de la clé qui a produit ce chiffré ; ValueError si ce n'en est pas un."""
    m = MOTIF_CHIFFRE.match(chiffre)
    if not m:
        raise ValueError("pas un chiffré transit (attendu « vault:v<N>:… »)")
    return int(m.group("version"))


def _jeton_de_session() -> str:
    jeton = os.environ.get("BAO_TOKEN", "").strip()
    if jeton:
        return jeton
    fichier = Path.home() / ".vault-token"
    try:
        jeton = fichier.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        jeton = ""
    except OSError as exc:
        raise ConfigError(f"{fichier} illisible : {exc.strerror}") from exc
    if not jeton:
        raise ConfigError(
            "aucun jeton OpenBao : « bao login -method=oidc » ou BAO_TOKEN (AppRole medictl)"
        )
    return jeton


class ClientTransit:
    """Opérations de transit sur UNE clé. Le jeton n'apparaît dans aucun message ni journal."""

    def __init__(
        self,
        adresse: str,
        jeton: str,
        cle: str,
        *,
        montage: str = "transit",
        verification: str | bool = True,
        delai: float = 10,
        session: requests.Session | None = None,
    ) -> None:
        if not adresse.startswith("https://"):
            raise ConfigError(f"BAO_ADDR doit être en https:// (reçu « {adresse} »)")
        self.base = f"{adresse.rstrip('/')}/v1/{montage.strip('/')}"
        self.cle = cle
        self.delai = delai
        self.session = session or requests.Session()
        self.session.headers["X-Vault-Token"] = jeton
        # verify= est passé à CHAQUE requête : un « session.verify » serait remplacé en silence par
        # REQUESTS_CA_BUNDLE ou CURL_CA_BUNDLE s'ils sont définis (même piège qu'en M02-E08).
        self.verification = verification

    def __repr__(self) -> str:  # jamais le jeton
        return f"ClientTransit(base={self.base!r}, cle={self.cle!r})"

    @classmethod
    def depuis_environnement(cls, cle: str, montage: str = "transit") -> ClientTransit:
        adresse = os.environ.get("BAO_ADDR", "").strip()
        if not adresse:
            raise ConfigError("BAO_ADDR non défini (https://openbao.par1.medisphere.internal:8200)")
        ca = os.environ.get("BAO_CACERT", "").strip()
        return cls(adresse, _jeton_de_session(), cle, montage=montage, verification=ca or True)

    # --- appel unique à l'API ------------------------------------------------------------------
    def _post(self, operation: str, corps: dict[str, Any]) -> dict[str, Any]:
        url = f"{self.base}/{operation}/{self.cle}"
        try:
            r = self.session.post(url, json=corps, timeout=self.delai, verify=self.verification)
        except requests.exceptions.SSLError as exc:
            raise ErreurApi(f"TLS refusé par {self.base} (autorité ? BAO_CACERT)") from exc
        except requests.exceptions.RequestException as exc:
            raise ErreurApi(f"OpenBao injoignable ({type(exc).__name__})") from exc
        if r.status_code == 403:
            raise ErreurApi(f"{operation} sur la clé {self.cle} refusé (jeton expiré ou politique)")
        if r.status_code >= 400:
            erreurs = "; ".join(r.json().get("errors", [])) if r.content else ""
            raise ErreurApi(
                f"{operation} sur la clé {self.cle} : HTTP {r.status_code} {erreurs}".strip()
            )
        return r.json()["data"]

    def _lot(self, operation: str, entrees: list[dict[str, str]], champ: str) -> list[str]:
        """batch_input : une requête pour plusieurs éléments ; une erreur possible par élément."""
        sortie: list[str] = []
        for debut in range(0, len(entrees), TAILLE_LOT):
            resultats = self._post(operation, {"batch_input": entrees[debut : debut + TAILLE_LOT]})[
                "batch_results"
            ]
            for i, res in enumerate(resultats, start=debut):
                if res.get("error"):
                    raise ErreurApi(f"{operation}, élément {i} : {res['error']}")
                sortie.append(res[champ])
        return sortie

    # --- opérations ---------------------------------------------------------------------------
    def chiffrer(self, clairs: Iterable[bytes]) -> list[str]:
        entrees = [{"plaintext": base64.b64encode(c).decode("ascii")} for c in clairs]
        return self._lot("encrypt", entrees, "ciphertext") if entrees else []

    def dechiffrer(self, chiffres: Iterable[str]) -> list[bytes]:
        entrees = [{"ciphertext": c} for c in chiffres]
        if not entrees:
            return []
        return [base64.b64decode(p) for p in self._lot("decrypt", entrees, "plaintext")]

    def rechiffrer(self, chiffres: Iterable[str]) -> list[str]:
        entrees = [{"ciphertext": c} for c in chiffres]
        return self._lot("rewrap", entrees, "ciphertext") if entrees else []


# --- champs d'un document JSON (liste de fiches ou fiche unique) ----------------------------------
def _valeurs(donnees: Any, champs: set[str]) -> list[tuple[dict[str, Any], str]]:
    fiches = donnees if isinstance(donnees, list) else [donnees]
    trouves = []
    for fiche in fiches:
        if not isinstance(fiche, dict):
            raise ConfigError("le document doit être un objet JSON ou une liste d'objets")
        trouves.extend((fiche, c) for c in sorted(champs) if fiche.get(c) is not None)
    return trouves


def _appliquer(
    donnees: Any,
    champs: set[str],
    operation: Callable[[list[Any]], list[Any]],
    avant: Callable[[Any], Any],
    apres: Callable[[Any], Any],
) -> int:
    cibles = _valeurs(donnees, champs)
    resultats = operation([avant(f[c]) for f, c in cibles])
    for (fiche, champ), valeur in zip(cibles, resultats, strict=True):
        fiche[champ] = apres(valeur)
    return len(cibles)


def chiffrer_champs(donnees: Any, champs: set[str], client: ClientTransit) -> int:
    """Chiffre les champs en clair ; un champ déjà chiffré est laissé tel quel (idempotent)."""
    cibles = [(f, c) for f, c in _valeurs(donnees, champs) if not MOTIF_CHIFFRE.match(str(f[c]))]
    resultats = client.chiffrer(str(f[c]).encode("utf-8") for f, c in cibles)
    for (fiche, champ), valeur in zip(cibles, resultats, strict=True):
        fiche[champ] = valeur
    return len(cibles)


def dechiffrer_champs(donnees: Any, champs: set[str], client: ClientTransit) -> int:
    return _appliquer(donnees, champs, client.dechiffrer, str, lambda b: b.decode("utf-8"))


def rechiffrer_champs(donnees: Any, champs: set[str], client: ClientTransit) -> int:
    """Passe tous les champs à la dernière version de la clé (rewrap) ; le clair ne sort jamais."""
    return _appliquer(donnees, champs, client.rechiffrer, str, str)
