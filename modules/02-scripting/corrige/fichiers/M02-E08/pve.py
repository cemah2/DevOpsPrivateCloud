"""Accès à l'API Proxmox VE pour medictl (M02-E08).

Lit la configuration au format de ~/.config/workbook/pve-api.env (M00-E17) sans
l'exécuter, puis ouvre une connexion proxmoxer authentifiée par jeton d'API,
certificat du serveur VÉRIFIÉ avec l'autorité indiquée par PVE_CACERT.

Le secret du jeton n'apparaît jamais dans repr(), dans un message d'erreur ni
dans les journaux.
"""

import os
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit

from proxmoxer import ProxmoxAPI

FICHIER_ENV_DEFAUT = Path.home() / ".config" / "workbook" / "pve-api.env"
CLES_OBLIGATOIRES = ("PVE_API_URL", "PVE_NODE", "PVE_TOKEN_ID", "PVE_TOKEN_SECRET")


class ConfigError(Exception):
    """Configuration absente, incomplète ou invalide (jamais de secret dans le message)."""


@dataclass(frozen=True)
class PveConfig:
    """Paramètres de connexion à l'API Proxmox VE."""

    api_url: str  # https://<hôte>:8006/api2/json
    node: str  # nom du nœud Proxmox
    token_id: str  # utilisateur@domaine!jeton, ex. wb-automation@pve!lab
    token_secret: str = field(repr=False)  # exclu de repr() : jamais affiché
    cacert: Path | None = None  # autorité qui a signé le certificat de pve01

    @property
    def hote(self) -> str:
        return urlsplit(self.api_url).hostname or ""

    @property
    def port(self) -> int:
        return urlsplit(self.api_url).port or 8006

    @property
    def utilisateur(self) -> str:
        return self.token_id.partition("!")[0]

    @property
    def nom_jeton(self) -> str:
        return self.token_id.partition("!")[2]


def _valeur(brute: str, chemin: Path, numero: int) -> str:
    """Interprète la partie droite d'une affectation shell simple."""
    brute = brute.strip()
    if brute[:1] in ("'", '"'):
        guillemet = brute[0]
        fin = brute.find(guillemet, 1)
        if fin == -1:
            raise ConfigError(f"{chemin}:{numero} : guillemet non fermé")
        contenu = brute[1:fin]
        # Comme en shell : pas d'expansion entre apostrophes, expansion entre guillemets.
        return contenu if guillemet == "'" else os.path.expandvars(contenu)
    # Valeur sans guillemets : un « # » précédé d'un blanc ouvre un commentaire.
    contenu = brute.split(" #", 1)[0].split("\t#", 1)[0].strip()
    return os.path.expandvars(contenu)


def lire_fichier_env(chemin: Path) -> dict[str, str]:
    """Lit un fichier « CLE=valeur » (syntaxe shell simple) sans l'exécuter."""
    valeurs: dict[str, str] = {}
    try:
        texte = chemin.read_text(encoding="utf-8")
    except OSError as exc:
        raise ConfigError(
            f"fichier de configuration illisible : {chemin} ({exc.strerror})"
        ) from None
    for numero, ligne in enumerate(texte.splitlines(), start=1):
        ligne = ligne.strip()
        if not ligne or ligne.startswith("#"):
            continue
        if ligne.startswith("export "):
            ligne = ligne.removeprefix("export ").lstrip()
        cle, egal, reste = ligne.partition("=")
        if not egal or not cle.isidentifier():
            raise ConfigError(f"{chemin}:{numero} : ligne non reconnue (attendu CLE=valeur)")
        valeurs[cle] = _valeur(reste, chemin, numero)
    return valeurs


def charger_config(chemin: Path | None = None) -> PveConfig:
    """Charge la configuration : argument, sinon $MEDICTL_ENV_FILE, sinon le fichier par défaut."""
    if chemin is None:
        chemin = Path(os.environ.get("MEDICTL_ENV_FILE", FICHIER_ENV_DEFAUT))
    valeurs = lire_fichier_env(chemin)

    manquantes = [cle for cle in CLES_OBLIGATOIRES if not valeurs.get(cle)]
    if manquantes:
        raise ConfigError(f"{chemin} : variable(s) absente(s) ou vide(s) : {', '.join(manquantes)}")

    url = urlsplit(valeurs["PVE_API_URL"])
    if url.scheme != "https" or not url.hostname:
        raise ConfigError(f"{chemin} : PVE_API_URL doit être une URL https://…")
    if not url.path.rstrip("/").endswith("/api2/json"):
        raise ConfigError(f"{chemin} : PVE_API_URL doit se terminer par /api2/json")
    if valeurs["PVE_TOKEN_ID"].count("!") != 1:
        raise ConfigError(f"{chemin} : PVE_TOKEN_ID doit avoir la forme utilisateur@domaine!jeton")

    cacert = None
    if valeurs.get("PVE_CACERT"):
        cacert = Path(valeurs["PVE_CACERT"]).expanduser()
        if not cacert.is_file():
            raise ConfigError(f"{chemin} : PVE_CACERT ne désigne pas un fichier lisible : {cacert}")

    return PveConfig(
        api_url=valeurs["PVE_API_URL"].rstrip("/"),
        node=valeurs["PVE_NODE"],
        token_id=valeurs["PVE_TOKEN_ID"],
        token_secret=valeurs["PVE_TOKEN_SECRET"],
        cacert=cacert,
    )


def connexion(cfg: PveConfig, timeout: float = 10) -> ProxmoxAPI:
    """Ouvre un client proxmoxer. Aucun appel réseau n'est fait ici.

    verify_ssl reçoit le chemin de l'autorité (transmis tel quel à requests),
    ou True pour le magasin du système : jamais False.
    """
    return ProxmoxAPI(
        cfg.hote,
        port=cfg.port,
        user=cfg.utilisateur,
        token_name=cfg.nom_jeton,
        token_value=cfg.token_secret,
        verify_ssl=str(cfg.cacert) if cfg.cacert else True,
        timeout=timeout,
    )
