#!/usr/bin/env python3
"""Rapport de capacité mémoire du lab — version corrigée (revue M02-E23).

Usage :
  rapport_capacite.py [--depuis-fichier F] [--seuil POURCENT] [--ram-hote-gio N] [--csv F]

Mémoire allouée (maxmem) des VMs QEMU, par pool, rapportée à la mémoire de l'hôte.
Les templates ne comptent pas (ils ne démarrent jamais) ; les VMs arrêtées comptent
(elles peuvent démarrer à tout moment : c'est de la capacité réservée).

Codes de sortie : 0 sous le seuil ; 1 seuil dépassé OU erreur (message explicite
sur stderr) ; 2 usage. Le cron (ou le timer systemd) n'a qu'à surveiller le code.

Configuration : variables PVE_API_URL, PVE_TOKEN_ID, PVE_TOKEN_SECRET, PVE_CACERT,
sinon ~/.config/workbook/pve-api.env (lu, jamais exécuté). Aucun secret dans ce fichier.
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import os
import shlex
import sys
from collections import defaultdict
from pathlib import Path

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

log = logging.getLogger("rapport_capacite")
GIO = 1024**3
FICHIER_ENV = Path("~/.config/workbook/pve-api.env").expanduser()


class Erreur(Exception):
    """Erreur prévue : message d'une ligne, code 1."""


def lire_env(chemin: Path) -> dict[str, str]:
    valeurs = {}
    if chemin.is_file():
        if chemin.stat().st_mode & 0o077:
            raise Erreur(f"{chemin} est lisible par d'autres que toi : corrige ses droits (600)")
        for ligne in chemin.read_text(encoding="utf-8").splitlines():
            morceaux = shlex.split(ligne, comments=True)
            if len(morceaux) == 1 and "=" in morceaux[0]:
                cle, val = morceaux[0].split("=", 1)
                valeurs[cle] = os.path.expanduser(os.path.expandvars(val))
    valeurs.update({k: v for k, v in os.environ.items() if k.startswith("PVE_") and v})
    manquantes = [
        k for k in ("PVE_API_URL", "PVE_TOKEN_ID", "PVE_TOKEN_SECRET") if k not in valeurs
    ]
    if manquantes:
        raise Erreur(f"configuration incomplète : {', '.join(manquantes)}")
    return valeurs


def session_api(cfg: dict[str, str]) -> requests.Session:
    """Session avec TLS vérifié, jeton dans un en-tête, reprises bornées sur GET."""
    session = requests.Session()
    session.verify = cfg.get("PVE_CACERT") or True  # jamais False
    session.headers["Authorization"] = (
        f"PVEAPIToken={cfg['PVE_TOKEN_ID']}={cfg['PVE_TOKEN_SECRET']}"
    )
    reprises = Retry(
        total=3, backoff_factor=1, status_forcelist=(502, 503, 504), allowed_methods={"GET"}
    )
    session.mount("https://", HTTPAdapter(max_retries=reprises))
    return session


def lire_ressources(fichier: Path | None) -> list[dict]:
    if fichier:
        try:
            return json.loads(fichier.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise Erreur(f"export illisible {fichier} : {exc}") from exc
    cfg = lire_env(FICHIER_ENV)
    url = cfg["PVE_API_URL"].rstrip("/") + "/cluster/resources"
    try:
        reponse = session_api(cfg).get(url, timeout=(5, 30))
    except requests.exceptions.SSLError as exc:
        raise Erreur(f"certificat de Proxmox refusé (PVE_CACERT ?) : {exc}") from exc
    except requests.exceptions.RequestException as exc:
        raise Erreur(f"Proxmox injoignable : {exc}") from exc
    if reponse.status_code != 200:
        raise Erreur(f"API Proxmox : HTTP {reponse.status_code} {reponse.reason}")
    return reponse.json()["data"]


def ram_hote(ressources: list[dict], ram_hote_gio: float | None) -> float:
    """Mémoire totale des nœuds visibles, en Gio. Un jeton sans Sys.Audit ne voit
    aucun nœud : il faut alors fournir --ram-hote-gio (et savoir que les VMs hors
    du pool sont invisibles, donc le rapport incomplet)."""
    if ram_hote_gio:
        return ram_hote_gio
    noeuds = [r for r in ressources if r.get("type") == "node" and r.get("maxmem")]
    if not noeuds:
        raise Erreur(
            "aucun nœud visible (jeton sans Sys.Audit ?) : indique --ram-hote-gio, "
            "ou utilise un jeton d'audit qui voit tout l'hôte"
        )
    return sum(n["maxmem"] for n in noeuds) / GIO


def calculer(ressources: list[dict], totale: float) -> list[dict]:
    par_pool: dict[str, float] = defaultdict(float)  # nouvel objet à chaque appel
    for r in ressources:
        if r.get("type") == "qemu" and str(r.get("template", 0)) != "1":
            par_pool[r.get("pool") or "(hors pool)"] += r.get("maxmem", 0) / GIO
    return [
        {
            "pool": pool,
            "ram_gio": round(gio, 1),
            "pourcentage": round(gio / totale * 100, 1),
        }
        for pool, gio in sorted(par_pool.items())
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--depuis-fichier", type=Path, help="export JSON de /cluster/resources")
    parser.add_argument("--seuil", type=float, default=80.0, help="alerte au-delà (%%)")
    parser.add_argument("--ram-hote-gio", type=float, help="mémoire de l'hôte si non visible")
    parser.add_argument("--csv", type=Path, help="écrit aussi le rapport dans ce fichier CSV")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s", stream=sys.stderr)

    try:
        ressources = lire_ressources(args.depuis_fichier)
        totale = ram_hote(ressources, args.ram_hote_gio)
        lignes = calculer(ressources, totale)
    except Erreur as exc:
        log.error("%s", exc)
        return 1

    ecrivain = csv.DictWriter(sys.stdout, fieldnames=["pool", "ram_gio", "pourcentage"])
    ecrivain.writeheader()
    ecrivain.writerows(lignes)
    if args.csv:
        temporaire = args.csv.with_name(f".{args.csv.name}.tmp")
        with temporaire.open("w", newline="", encoding="utf-8") as f:
            sortie = csv.DictWriter(f, fieldnames=["pool", "ram_gio", "pourcentage"])
            sortie.writeheader()
            sortie.writerows(lignes)
        temporaire.replace(args.csv)  # jamais de rapport à moitié écrit

    allouee = sum(ligne["ram_gio"] for ligne in lignes)
    taux = allouee / totale * 100
    message = (
        f"{allouee:.1f} Gio alloués sur {totale:.1f} Gio ({taux:.0f} %, seuil {args.seuil:.0f} %)"
    )
    if taux > args.seuil:
        log.error("ALERTE capacité : %s", message)
        return 1
    log.info("capacité : %s", message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
