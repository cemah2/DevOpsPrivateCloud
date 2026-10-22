#!/usr/bin/env python3
"""synchro-gitlab.py — appartenances aux groupes GitLab tirées de l'annuaire (M24-E11, PLAT-2511).

GitLab CE ne synchronise pas les groupes OIDC (fonction Premium) : cet outil applique la table
outils/synchro-gitlab.yml à partir des fichiers de l'annuaire (annuaire/personnes.yml,
annuaire/groupes.yml), par l'API REST v4 de GitLab.

Par défaut, il AFFICHE les écarts et ne change rien (code 0, ou 3 s'il y a des écarts avec
--verifier). Avec --appliquer, il les corrige.

Bornes (voulues) :
  - seuls les membres DIRECTS des groupes GitLab cités dans la table sont lus et modifiés ;
  - seules les personnes de annuaire/personnes.yml sont gérées : root, svc-*, robots et comptes de
    projet ne sont jamais touchés ;
  - une personne « disabled » perd ses appartenances ;
  - le niveau Owner n'est jamais donné ni retiré, même si le compte de synchronisation est Owner (GitLab
    réserve la gestion des membres d'un groupe aux Owners) : signalé, laissé à un humain ;
  - une personne absente de GitLab (jamais connectée, pas de compte) est signalée, sans erreur.

Environnement :
  GITLAB_URL            défaut : CI_SERVER_URL, sinon https://git01.par1.medisphere.internal
  GITLAB_SYNCHRO_JETON  jeton personnel « api » de svc-synchro-identite (jamais affiché)
  REQUESTS_CA_BUNDLE    magasin à utiliser (défaut de l'outil : /etc/ssl/certs/ca-certificates.crt,
                        qui contient la racine MédiSphère sur adm01 et runner01)

Codes : 0 conforme ou appliqué ; 1 erreur d'API ou de données ; 2 usage ; 3 écarts (--verifier).
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote

import requests
import yaml

NIVEAUX = {"reporter": 20, "developer": 30, "maintainer": 40}
NOMS_NIVEAUX = {10: "guest", 15: "planner", 20: "reporter", 30: "developer", 40: "maintainer", 50: "owner"}
OWNER = 50
RACINE = Path(__file__).resolve().parent.parent


class ErreurDonnees(Exception):
    """Fichier de l'annuaire ou de la table incohérent."""


@dataclass(frozen=True)
class Action:
    groupe: str
    personne: str
    avant: int | None
    apres: int | None
    note: str = ""

    def __str__(self) -> str:
        av = NOMS_NIVEAUX.get(self.avant, "—") if self.avant else "—"
        ap = NOMS_NIVEAUX.get(self.apres, "—") if self.apres else "—"
        suffixe = f" ({self.note})" if self.note else ""
        return f"{self.groupe:<12} {self.personne:<22} {av:>10} → {ap:<10}{suffixe}"


def lire_yaml(chemin: Path, cle: str) -> list[dict]:
    with chemin.open(encoding="utf-8") as f:
        donnees = yaml.safe_load(f) or {}
    valeur = donnees.get(cle)
    if not isinstance(valeur, list):
        raise ErreurDonnees(f"{chemin} : clé « {cle} » absente ou qui n'est pas une liste")
    return valeur


def calculer_cible(personnes: list[dict], groupes: list[dict], table: list[dict]) -> dict[str, dict[str, int]]:
    """Niveau voulu par groupe GitLab et par personne ACTIVE : {gitlab: {identifiant: niveau}}.

    Fonction pure (aucun appel réseau) : c'est elle que l'on teste.
    """
    actives: set[str] = set()
    connues: set[str] = set()
    for p in personnes:
        ident = str(p.get("identifiant", ""))
        if not ident or "<" in ident:
            raise ErreurDonnees(f"personnes.yml : identifiant vide ou non remplacé ({ident!r})")
        if ident in connues:
            raise ErreurDonnees(f"personnes.yml : identifiant en double ({ident})")
        connues.add(ident)
        if p.get("etat", "present") != "disabled":
            actives.add(ident)

    membres: dict[str, set[str]] = {}
    for g in groupes:
        nom = str(g.get("nom", ""))
        liste = g.get("membres") or []
        inconnus = [m for m in liste if m not in connues]
        if inconnus:
            raise ErreurDonnees(f"groupes.yml : {nom} cite des personnes inconnues : {', '.join(inconnus)}")
        membres[nom] = set(liste)

    cible: dict[str, dict[str, int]] = {}
    for ligne in table:
        annuaire, gitlab, niveau = ligne.get("annuaire"), ligne.get("gitlab"), ligne.get("niveau")
        if annuaire not in membres:
            raise ErreurDonnees(f"synchro-gitlab.yml : groupe de l'annuaire inconnu : {annuaire}")
        if niveau not in NIVEAUX:
            raise ErreurDonnees(f"synchro-gitlab.yml : niveau refusé pour {annuaire} → {gitlab} : {niveau}")
        if not gitlab or "/" in str(gitlab):
            raise ErreurDonnees(f"synchro-gitlab.yml : groupe GitLab de premier niveau attendu : {gitlab!r}")
        groupe_cible = cible.setdefault(str(gitlab), {})
        for personne in membres[annuaire] & actives:
            groupe_cible[personne] = max(groupe_cible.get(personne, 0), NIVEAUX[niveau])
    return cible


def calculer_actions(cible: dict[str, int], actuels: dict[str, int], gerees: set[str], groupe: str,
                     existants: set[str]) -> list[Action]:
    """Écarts entre la cible et les membres directs actuels d'UN groupe GitLab (fonction pure).

    gerees : identifiants de toutes les personnes de l'annuaire (actives ou non) ;
    existants : identifiants qui ont un compte GitLab.
    """
    actions: list[Action] = []
    for personne in sorted(gerees):
        voulu, avant = cible.get(personne), actuels.get(personne)
        if voulu == avant:
            continue
        if avant == OWNER:
            actions.append(Action(groupe, personne, avant, avant, "Owner : laissé tel quel, à revoir à la main"))
            continue
        if voulu is not None and personne not in existants:
            actions.append(Action(groupe, personne, None, voulu, "pas de compte GitLab : première connexion SSO à venir"))
            continue
        actions.append(Action(groupe, personne, avant, voulu))
    return actions


class GitLab:
    def __init__(self, url: str, jeton: str) -> None:
        self.base = url.rstrip("/") + "/api/v4"
        self.session = requests.Session()
        self.session.headers["PRIVATE-TOKEN"] = jeton
        self.session.verify = os.environ.get("REQUESTS_CA_BUNDLE", "/etc/ssl/certs/ca-certificates.crt")

    def _appel(self, methode: str, chemin: str, **kw) -> requests.Response:
        r = self.session.request(methode, self.base + chemin, timeout=15, **kw)
        if r.status_code >= 400:
            # Jamais le jeton ni les en-têtes dans le message : seulement la méthode, le chemin, le code.
            raise RuntimeError(f"{methode} {chemin} : HTTP {r.status_code} {r.text[:200]}")
        return r

    def pages(self, chemin: str) -> list[dict]:
        resultats, page = [], 1
        while True:
            r = self._appel("GET", chemin, params={"per_page": 100, "page": page})
            resultats.extend(r.json())
            suivante = r.headers.get("X-Next-Page", "")
            if not suivante:
                return resultats
            page = int(suivante)

    def groupe(self, chemin: str) -> dict:
        return self._appel("GET", f"/groups/{quote(chemin, safe='')}").json()

    def membres_directs(self, id_groupe: int) -> dict[str, int]:
        return {m["username"]: m["access_level"] for m in self.pages(f"/groups/{id_groupe}/members")}

    def id_utilisateur(self, identifiant: str) -> int | None:
        r = self._appel("GET", "/users", params={"username": identifiant})
        trouves = r.json()
        return trouves[0]["id"] if trouves else None

    def ajouter(self, id_groupe: int, id_util: int, niveau: int) -> None:
        self._appel("POST", f"/groups/{id_groupe}/members", data={"user_id": id_util, "access_level": niveau})

    def modifier(self, id_groupe: int, id_util: int, niveau: int) -> None:
        self._appel("PUT", f"/groups/{id_groupe}/members/{id_util}", data={"access_level": niveau})

    def retirer(self, id_groupe: int, id_util: int) -> None:
        self._appel("DELETE", f"/groups/{id_groupe}/members/{id_util}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Appartenances aux groupes GitLab tirées de l'annuaire (M24-E11).")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--appliquer", action="store_true", help="corrige les écarts (sinon : aperçu)")
    mode.add_argument("--verifier", action="store_true", help="aperçu, code 3 s'il y a des écarts")
    parser.add_argument("--racine", type=Path, default=RACINE, help="racine du dépôt plateforme/identite")
    args = parser.parse_args()

    jeton = os.environ.get("GITLAB_SYNCHRO_JETON", "")
    if not jeton:
        print("synchro-gitlab : GITLAB_SYNCHRO_JETON absent (variable protégée de CI, ou "
              "~/.config/workbook/gitlab-synchro.env sur adm01)", file=sys.stderr)
        return 2
    url = os.environ.get("GITLAB_URL") or os.environ.get("CI_SERVER_URL") or "https://git01.par1.medisphere.internal"

    try:
        personnes = lire_yaml(args.racine / "annuaire/personnes.yml", "annuaire_personnes")
        groupes = lire_yaml(args.racine / "annuaire/groupes.yml", "annuaire_groupes")
        table = lire_yaml(args.racine / "outils/synchro-gitlab.yml", "synchro_gitlab")
        cible = calculer_cible(personnes, groupes, table)
    except (OSError, yaml.YAMLError, ErreurDonnees) as e:
        print(f"synchro-gitlab : {e}", file=sys.stderr)
        return 1
    gerees = {str(p["identifiant"]) for p in personnes}

    gl = GitLab(url, jeton)
    ecarts = erreurs = 0
    try:
        for chemin in sorted(cible):
            groupe = gl.groupe(chemin)
            actuels = {u: n for u, n in gl.membres_directs(groupe["id"]).items() if u in gerees}
            ids = {p: gl.id_utilisateur(p) for p in gerees if p in cible[chemin] or p in actuels}
            existants = {p for p, i in ids.items() if i is not None}
            for action in calculer_actions(cible[chemin], actuels, gerees, chemin, existants):
                ecarts += 1
                print(("APPLIQUÉ  " if args.appliquer and action.note == "" else "ÉCART    ") + str(action))
                if not args.appliquer or action.note:
                    continue
                id_util = ids[action.personne]
                assert id_util is not None
                if action.avant is None:
                    gl.ajouter(groupe["id"], id_util, action.apres)
                elif action.apres is None:
                    gl.retirer(groupe["id"], id_util)
                else:
                    gl.modifier(groupe["id"], id_util, action.apres)
    except (RuntimeError, requests.RequestException) as e:
        print(f"synchro-gitlab : {e}", file=sys.stderr)
        erreurs += 1

    print(f"synchro-gitlab : {len(cible)} groupe(s) GitLab, {ecarts} écart(s)"
          + (", appliqués" if args.appliquer else ", rien n'a été changé") + ".")
    if erreurs:
        return 1
    return 3 if (args.verifier and ecarts) else 0


if __name__ == "__main__":
    sys.exit(main())
