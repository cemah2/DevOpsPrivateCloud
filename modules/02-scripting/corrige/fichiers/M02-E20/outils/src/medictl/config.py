"""Configuration de medictl (M02-E19).

Ordre de priorité, du plus faible au plus fort :
1. le fichier d'accès (format M00-E17) : ``MEDICTL_ENV_FILE``, sinon
   ``~/.config/workbook/pve-api.env`` ;
2. les variables d'environnement ``PVE_*`` (CI, essais ponctuels).

Règles de sécurité :
- le fichier est LU, jamais exécuté (pas de ``source``, pas d'``eval``) ;
- un fichier accessible au groupe ou aux autres est refusé ;
- le secret n'apparaît ni dans ``repr()``, ni dans les journaux, ni en argument ;
- TLS toujours vérifié : ``PVE_CACERT`` si défini, sinon le magasin du système
  (paquet ``ca-certificates`` de Debian). Le chemin est passé à CHAQUE requête : les
  variables ``REQUESTS_CA_BUNDLE``/``CURL_CA_BUNDLE`` ne peuvent pas le remplacer.
"""

from __future__ import annotations

import os
import shlex
import stat
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit

from medictl.erreurs import ConfigError

FICHIER_DEFAUT = "~/.config/workbook/pve-api.env"
# Magasin de certificats du système (Debian) : requests, livré avec certifi, ne l'utilise
# pas de lui-même avec verify=True.
MAGASIN_SYSTEME = "/etc/ssl/certs/ca-certificates.crt"
CLES = ("PVE_API_URL", "PVE_NODE", "PVE_TOKEN_ID", "PVE_TOKEN_SECRET", "PVE_CACERT")
OBLIGATOIRES = ("PVE_API_URL", "PVE_NODE", "PVE_TOKEN_ID", "PVE_TOKEN_SECRET")


@dataclass(frozen=True)
class PveConfig:
    api_url: str
    node: str
    token_id: str
    token_secret: str = field(repr=False)
    cacert: str | None = None
    sources: dict[str, str] = field(default_factory=dict, compare=False)

    @property
    def hote(self) -> str:
        return urlsplit(self.api_url).hostname or ""

    @property
    def port(self) -> int:
        return urlsplit(self.api_url).port or 8006

    @property
    def utilisateur(self) -> str:
        return self.token_id.split("!", 1)[0]

    @property
    def nom_jeton(self) -> str:
        return self.token_id.split("!", 1)[1]

    @property
    def verification_tls(self) -> str | bool:
        """Valeur passée à requests (``verify``) : un chemin de CA, ou True. Jamais False.

        Sans PVE_CACERT : le magasin du système s'il existe ; sinon True (racines de certifi).
        """
        if self.cacert:
            return self.cacert
        return MAGASIN_SYSTEME if os.path.isfile(MAGASIN_SYSTEME) else True

    def affichable(self) -> dict[str, str]:
        """Configuration effective, secret masqué, avec l'origine de chaque valeur."""
        valeurs = {
            "PVE_API_URL": self.api_url,
            "PVE_NODE": self.node,
            "PVE_TOKEN_ID": self.token_id,
            "PVE_TOKEN_SECRET": "****" if self.token_secret else "(vide)",
            "PVE_CACERT": self.cacert or "(magasin de certificats du système)",
        }
        return {cle: f"{val}   [{self.sources.get(cle, 'défaut')}]" for cle, val in valeurs.items()}


def lire_fichier_env(chemin: Path) -> dict[str, str]:
    """Lit un fichier ``CLE=valeur`` de syntaxe shell simple, sans l'exécuter.

    Gère les commentaires, ``export``, les guillemets simples et doubles, et le
    développement de ``$HOME`` / ``~`` hors guillemets simples (le fichier de
    M00-E17 écrit ``PVE_CACERT="$HOME/.config/workbook/pve-root-ca.pem"``).
    """
    valeurs: dict[str, str] = {}
    for numero, ligne in enumerate(chemin.read_text(encoding="utf-8").splitlines(), 1):
        brute = ligne.strip()
        if not brute or brute.startswith("#"):
            continue
        brute = brute.removeprefix("export ").strip()
        try:
            morceaux = shlex.split(brute, comments=True, posix=True)
        except ValueError as exc:
            raise ConfigError(f"{chemin}, ligne {numero} : syntaxe invalide ({exc})") from exc
        if len(morceaux) != 1 or "=" not in morceaux[0]:
            raise ConfigError(f"{chemin}, ligne {numero} : « CLE=valeur » attendu")
        cle, valeur = morceaux[0].split("=", 1)
        if not brute.split("=", 1)[1].startswith("'"):
            valeur = os.path.expanduser(os.path.expandvars(valeur))
        valeurs[cle] = valeur
    return valeurs


def _verifier_droits(chemin: Path) -> None:
    mode = stat.S_IMODE(chemin.stat().st_mode)
    if mode & 0o077:
        raise ConfigError(
            f"{chemin} est accessible à d'autres que son propriétaire (mode {mode:o}) : "
            "il contient un secret, corrige ses droits avant de continuer"
        )


def charger_config(environ: dict[str, str] | None = None) -> PveConfig:
    """Assemble la configuration effective et la valide."""
    env = dict(os.environ if environ is None else environ)
    chemin = Path(os.path.expanduser(env.get("MEDICTL_ENV_FILE", FICHIER_DEFAUT)))

    valeurs: dict[str, str] = {}
    sources: dict[str, str] = {}
    if chemin.is_file():
        _verifier_droits(chemin)
        for cle, val in lire_fichier_env(chemin).items():
            if cle in CLES:
                valeurs[cle] = val
                sources[cle] = str(chemin)
    for cle in CLES:
        if env.get(cle):
            valeurs[cle] = env[cle]
            sources[cle] = "environnement"

    manquantes = [c for c in OBLIGATOIRES if not valeurs.get(c)]
    if manquantes:
        origine = str(chemin) if chemin.is_file() else f"{chemin} (absent)"
        raise ConfigError(
            f"configuration incomplète, manque : {', '.join(manquantes)} "
            f"(fichier {origine} ou variables d'environnement)"
        )

    url = urlsplit(valeurs["PVE_API_URL"])
    if url.scheme != "https" or not url.hostname:
        raise ConfigError("PVE_API_URL doit être une URL https:// (TLS obligatoire)")
    if url.path.rstrip("/") != "/api2/json":
        raise ConfigError("PVE_API_URL doit se terminer par /api2/json")
    if "!" not in valeurs["PVE_TOKEN_ID"]:
        raise ConfigError("PVE_TOKEN_ID doit avoir la forme utilisateur@domaine!jeton")
    cacert = valeurs.get("PVE_CACERT") or None
    if cacert and not os.access(cacert, os.R_OK):
        raise ConfigError(f"certificat d'autorité illisible : {cacert} (PVE_CACERT)")

    return PveConfig(
        api_url=valeurs["PVE_API_URL"],
        node=valeurs["PVE_NODE"],
        token_id=valeurs["PVE_TOKEN_ID"],
        token_secret=valeurs["PVE_TOKEN_SECRET"],
        cacert=cacert,
        sources=sources,
    )
