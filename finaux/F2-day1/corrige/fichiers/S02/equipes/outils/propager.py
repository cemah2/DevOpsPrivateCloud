#!/usr/bin/env python3
"""propager.py — porte le rendu de plateforme/equipes dans les dépôts qui appliquent (F2-S02, PLAT-3202).

Pour chaque cible de config/plateforme.yaml (identite, secrets, grafana, k8s, gitops) :
  - compare rendu/<cible>/… aux fichiers que le générateur POSSÈDE dans le dépôt (chemins de la cible,
    branche main) : création, modification, suppression ; il ne lit ni ne touche rien d'autre ;
  - --apercu : affiche les différences (diff unifié), ne change rien (pipeline de MR) ;
  - --appliquer : un commit sur une branche equipes/<sha court>, une MR « chore(equipes): … » étiquetée
    equipe-en-code, fusion automatique quand SON pipeline réussit (auto_merge). Une MR de propagation plus
    ancienne encore ouverte est fermée (le nouveau rendu la remplace : il est complet).

Le dépôt cible garde ses propres contrôles (lint, plan OpenTofu, ansible --check, validation des
manifestes) : un rendu qu'il refuse n'est jamais fusionné. Ses règles d'application décident ensuite
(RB-320 : automatique pour les fichiers générés, sauf destruction annoncée par un plan).

Environnement : GITLAB_EQUIPES_JETON (svc-equipes, Developer des dépôts cibles + droit de fusion),
CI_COMMIT_SHORT_SHA, CI_PROJECT_URL (lien dans la MR), REQUESTS_CA_BUNDLE.
Codes : 0 rien à faire ou fait ; 1 erreur ; 2 usage ; 3 différences (aperçu).
"""

from __future__ import annotations

import argparse
import base64
import difflib
import os
import sys
import time
from pathlib import Path
from urllib.parse import quote

import requests
import yaml

RACINE = Path(__file__).resolve().parent.parent


class Erreur(Exception):
    pass


class GitLab:
    def __init__(self, url: str, jeton: str) -> None:
        self.base = url.rstrip("/") + "/api/v4"
        self.s = requests.Session()
        self.s.headers["PRIVATE-TOKEN"] = jeton
        self.s.verify = os.environ.get("REQUESTS_CA_BUNDLE", "/etc/ssl/certs/ca-certificates.crt")

    def appel(self, methode: str, chemin: str, ok404: bool = False, **kw) -> requests.Response | None:
        r = self.s.request(methode, self.base + chemin, timeout=30, **kw)
        if ok404 and r.status_code == 404:
            return None
        if r.status_code >= 400:
            raise Erreur(f"{methode} {chemin} : HTTP {r.status_code} {r.text[:200]}")
        return r

    def arbre(self, projet: str, dossier: str) -> list[str]:
        chemins, page = [], 1
        while True:
            r = self.appel(
                "GET",
                f"/projects/{quote(projet, safe='')}/repository/tree",
                ok404=True,
                params={"ref": "main", "path": dossier.rstrip("/"), "recursive": "true", "per_page": 100, "page": page},
            )
            if r is None:
                return chemins
            chemins += [x["path"] for x in r.json() if x["type"] == "blob"]
            if not r.headers.get("X-Next-Page"):
                return chemins
            page = int(r.headers["X-Next-Page"])

    def lire(self, projet: str, chemin: str) -> str | None:
        r = self.appel(
            "GET",
            f"/projects/{quote(projet, safe='')}/repository/files/{quote(chemin, safe='')}",
            ok404=True,
            params={"ref": "main"},
        )
        if r is None:
            return None
        return base64.b64decode(r.json()["content"]).decode("utf-8")


def actions_pour(gl: GitLab, projet: str, possedes: list[str], rendu: Path) -> tuple[list[dict], list[str]]:
    voulus = (
        {str(f.relative_to(rendu)): f.read_text(encoding="utf-8") for f in sorted(rendu.rglob("*")) if f.is_file()}
        if rendu.exists()
        else {}
    )
    for chemin in voulus:
        if not any(chemin == p or (p.endswith("/") and chemin.startswith(p)) for p in possedes):
            raise Erreur(f"{projet} : le rendu contient {chemin}, hors des chemins possédés (config/plateforme.yaml)")
    existants: set[str] = set()
    for p in possedes:
        if p.endswith("/"):
            existants.update(gl.arbre(projet, p))
        elif gl.lire(projet, p) is not None:
            existants.add(p)
    actions, diffs = [], []
    for chemin in sorted(set(voulus) | existants):
        avant = gl.lire(projet, chemin) if chemin in existants else None
        apres = voulus.get(chemin)
        if avant == apres:
            continue
        if apres is None:
            # .gitkeep et fichiers non générés sous un dossier possédé : jamais supprimés.
            if chemin.endswith(".gitkeep"):
                continue
            actions.append({"action": "delete", "file_path": chemin})
        else:
            actions.append({"action": "update" if avant is not None else "create", "file_path": chemin, "content": apres})
        diffs += difflib.unified_diff(
            (avant or "").splitlines(keepends=True),
            (apres or "").splitlines(keepends=True),
            fromfile=f"{projet}:{chemin} (main)",
            tofile=f"{projet}:{chemin} (rendu)",
        )
    return actions, diffs


def proposer(gl: GitLab, projet: str, actions: list[dict], sha: str, lien: str) -> str:
    p = quote(projet, safe="")
    branche = f"equipes/{sha}"
    # Les MR de propagation précédentes encore ouvertes sont remplacées par celle-ci.
    for mr in gl.appel("GET", f"/projects/{p}/merge_requests", params={"state": "opened", "labels": "equipe-en-code"}).json():
        if mr["source_branch"].startswith("equipes/") and mr["source_branch"] != branche:
            gl.appel("PUT", f"/projects/{p}/merge_requests/{mr['iid']}", data={"state_event": "close"})
    gl.appel(
        "POST",
        f"/projects/{p}/repository/commits",
        json={
            "branch": branche,
            "start_branch": "main",
            "actions": actions,
            "commit_message": f"chore(equipes): rendu de plateforme/equipes@{sha}\n\nSource : {lien}\nGénéré par outils/propager.py (F2-S02).",
        },
    )
    mr = gl.appel(
        "POST",
        f"/projects/{p}/merge_requests",
        data={
            "source_branch": branche,
            "target_branch": "main",
            "remove_source_branch": "true",
            "title": f"chore(equipes): rendu de plateforme/equipes@{sha}",
            "labels": "equipe-en-code",
            "description": (
                f"Rendu complet des équipes décrites dans plateforme/equipes ({lien}).\n\n"
                "Changement relu dans plateforme/equipes ; cette MR se fusionne seule si son pipeline réussit "
                "(RB-320). Ne pas la modifier : corriger plateforme/equipes."
            ),
        },
    ).json()
    # Fusion automatique quand le pipeline de la MR réussit (paramètre auto_merge de GitLab 17+ ; l'ancien
    # nom merge_when_pipeline_succeeds est essayé si l'instance ne le connaît pas). Un pipeline peut ne pas
    # être encore créé : GitLab répond 405/422, on réessaie quelques fois.
    for _ in range(6):
        for param in ("auto_merge", "merge_when_pipeline_succeeds"):
            r = gl.s.put(f"{gl.base}/projects/{p}/merge_requests/{mr['iid']}/merge", data={param: "true"}, timeout=30)
            if r.status_code < 400:
                return mr["web_url"]
        time.sleep(10)
    return mr["web_url"] + " (fusion automatique NON posée : à fusionner après relecture)"


def main() -> int:
    parser = argparse.ArgumentParser(description="Propage le rendu des équipes dans les dépôts cibles (F2-S02).")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--apercu", action="store_true")
    mode.add_argument("--appliquer", action="store_true")
    parser.add_argument("--rendu", type=Path, default=RACINE / "rendu")
    args = parser.parse_args()
    jeton = os.environ.get("GITLAB_EQUIPES_JETON", "")
    if not jeton:
        print("propager : GITLAB_EQUIPES_JETON absent", file=sys.stderr)
        return 2
    cfg = yaml.safe_load((RACINE / "config/plateforme.yaml").read_text(encoding="utf-8"))
    gl = GitLab(cfg["gitlab"]["url"], jeton)
    sha = os.environ.get("CI_COMMIT_SHORT_SHA", "local")
    lien = os.environ.get("CI_PROJECT_URL", "plateforme/equipes") + f"/-/commit/{sha}"
    total = 0
    try:
        for cle, cible in cfg["cibles"].items():
            actions, diffs = actions_pour(gl, cible["projet"], cible["chemins"], args.rendu / cle)
            if not actions:
                print(f"propager : {cible['projet']} à jour")
                continue
            total += len(actions)
            print(f"propager : {cible['projet']} : {len(actions)} fichier(s) à changer")
            sys.stdout.writelines(diffs)
            if args.appliquer:
                print(f"propager : MR {proposer(gl, cible['projet'], actions, sha, lien)}")
    except (Erreur, requests.RequestException) as err:
        print(f"propager : {err}", file=sys.stderr)
        return 1
    return 3 if (args.apercu and total) else 0


if __name__ == "__main__":
    sys.exit(main())
