#!/usr/bin/env python3
"""gitlab_equipes.py — ce que GitLab doit contenir pour chaque équipe (plateforme/equipes, F2-S02).

Pour chaque équipe ACTIVE :
  1. le groupe GitLab <groupe> (privé) et ses comptes de service (svc-portail, config/plateforme.yaml) ;
     les appartenances des PERSONNES ne sont pas gérées ici mais par synchro-gitlab.py de
     plateforme/identite (M24-E11), à partir des fichiers rendus ;
  2. le projet <groupe>/gitops (index des services de l'équipe, lu par l'ApplicationSet <equipe>) ;
  3. le jeton de déploiement de GROUPE « argocd-lecture » (read_repository), rangé dans OpenBao
     kv/plateforme/argocd/depot-<equipe> (url, username, password) → ExternalSecret repo-creds-<equipe> ;
  4. le jeton d'accès de GROUPE « ci-promotion » (rôle Developer, portée api), rangé dans
     kv/<equipe>/ci/promotion (champ « jeton ») → lu par le composant promotion (M25-E10).
Pour chaque équipe RETIRÉE : les deux jetons sont révoqués (les groupes et projets restent : archives).

Un jeton n'est JAMAIS affiché ni écrit sur disque : il passe de la réponse de GitLab au corps de la
requête vers OpenBao, en mémoire. Rotation : un jeton qui expire dans moins de 30 jours, ou dont le
secret manque dans OpenBao, est révoqué et remplacé.

    uv run outils/gitlab_equipes.py            # aperçu : ce qui serait fait (lecture seule)
    uv run outils/gitlab_equipes.py --appliquer

Environnement : GITLAB_EQUIPES_JETON (jeton « api » du compte de service svc-equipes, lu dans
kv/plateforme/equipes/gitlab par la CI) ; BAO_ADDR et BAO_TOKEN (rôle JWT ci-plateforme-equipes, 10 min) ;
REQUESTS_CA_BUNDLE (défaut : magasin système, qui contient la racine MédiSphère sur runner01).
Codes : 0 conforme ou appliqué ; 1 erreur ; 2 usage ; 3 écarts (aperçu).
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
from pathlib import Path
from urllib.parse import quote

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))

from rendre import RACINE, Invalide, charger, normaliser

MARGE_ROTATION = dt.timedelta(days=30)
README_GITOPS = """# {groupe}/gitops

Index des services de l'équipe {nom}, lu par l'ApplicationSet « {nom} » d'Argo CD (plateforme/gitops,
généré par plateforme/equipes). Un service = un fichier `services/<service>.yaml` contenant :

```yaml
service: <service>
```

Argo CD crée alors une Application par environnement de l'équipe ({envs}) à partir du projet
`{groupe}/<service>-deploiement`, dossier `overlays/<environnement>`. Le modèle « Nouveau service » du
portail ouvre cette MR pour toi (F2-S04). Retirer un fichier retire l'Application, pas ce qu'elle a
déployé (RB-320).
"""


class Erreur(Exception):
    pass


class Api:
    def __init__(self, base: str, entetes: dict[str, str]) -> None:
        self.base = base.rstrip("/")
        self.s = requests.Session()
        self.s.headers.update(entetes)
        self.s.verify = os.environ.get("REQUESTS_CA_BUNDLE", "/etc/ssl/certs/ca-certificates.crt")

    def appel(self, methode: str, chemin: str, ok404: bool = False, **kw) -> requests.Response | None:
        r = self.s.request(methode, self.base + chemin, timeout=20, **kw)
        if ok404 and r.status_code == 404:
            return None
        if r.status_code >= 400:
            # Jamais le corps d'une requête (il peut contenir un jeton) : méthode, chemin, code.
            raise Erreur(f"{methode} {chemin} : HTTP {r.status_code}")
        return r


def expire_bientot(expires_at: str | None, aujourdhui: dt.date) -> bool:
    if not expires_at:
        return False
    return dt.date.fromisoformat(expires_at[:10]) - aujourdhui < MARGE_ROTATION


def bao_present(bao: Api, chemin: str) -> bool:
    return bao.appel("GET", f"/v1/kv/metadata/{chemin}", ok404=True) is not None


def bao_ecrire(bao: Api, chemin: str, donnees: dict[str, str]) -> None:
    bao.appel("POST", f"/v1/kv/data/{chemin}", json={"data": donnees})


def traiter(e: dict, cfg: dict, gl: Api, bao: Api | None, appliquer: bool, journal: list[str]) -> None:
    aujourdhui = dt.date.today()
    groupe_chemin = e["groupe_gitlab"]
    r = gl.appel("GET", f"/groups/{quote(groupe_chemin, safe='')}", ok404=True)
    groupe = r.json() if r is not None else None

    if e["etat"] != "active":
        if groupe is None:
            return
        for jeton in gl.appel("GET", f"/groups/{groupe['id']}/access_tokens").json():
            if jeton["name"] == "ci-promotion" and jeton.get("active"):
                journal.append(f"{e['nom']} : révoquer le jeton de groupe ci-promotion (équipe retirée)")
                if appliquer:
                    gl.appel("DELETE", f"/groups/{groupe['id']}/access_tokens/{jeton['id']}")
        for jeton in gl.appel("GET", f"/groups/{groupe['id']}/deploy_tokens").json():
            if jeton["name"] == "argocd-lecture" and not jeton.get("revoked"):
                journal.append(f"{e['nom']} : révoquer le jeton de déploiement argocd-lecture (équipe retirée)")
                if appliquer:
                    gl.appel("DELETE", f"/groups/{groupe['id']}/deploy_tokens/{jeton['id']}")
        return

    # 1. Groupe
    if groupe is None:
        journal.append(f"{e['nom']} : créer le groupe GitLab {groupe_chemin}")
        if not appliquer:
            return  # la suite dépend de l'identifiant du groupe
        groupe = gl.appel(
            "POST",
            "/groups",
            data={
                "name": groupe_chemin,
                "path": groupe_chemin,
                "visibility": cfg["gitlab"]["visibilite"],
                "description": f"{e['description']} — géré par plateforme/equipes ({e['ticket']})",
            },
        ).json()
    gid = groupe["id"]

    # 1 bis. Comptes de service membres du groupe (svc-portail : découverte du catalogue et modèles du
    # portail, M28). synchro-gitlab.py ne gère que les PERSONNES de l'annuaire : il ne les retire pas.
    membres = {m["username"]: m["access_level"] for m in gl.appel("GET", f"/groups/{gid}/members").json()}
    for compte, niveau in cfg["gitlab"].get("comptes_service_groupe", {}).items():
        if membres.get(compte, 0) >= niveau:
            continue
        journal.append(f"{e['nom']} : {compte} membre du groupe {groupe_chemin} (niveau {niveau})")
        if appliquer:
            trouves = gl.appel("GET", "/users", params={"username": compte}).json()
            if not trouves:
                raise Erreur(f"compte de service {compte} introuvable dans GitLab")
            if compte in membres:
                gl.appel("PUT", f"/groups/{gid}/members/{trouves[0]['id']}", data={"access_level": niveau})
            else:
                gl.appel("POST", f"/groups/{gid}/members", data={"user_id": trouves[0]["id"], "access_level": niveau})

    # 2. Projet <groupe>/gitops
    projet = f"{groupe_chemin}/gitops"
    if gl.appel("GET", f"/projects/{quote(projet, safe='')}", ok404=True) is None:
        journal.append(f"{e['nom']} : créer le projet {projet}")
        if appliquer:
            p = gl.appel(
                "POST",
                "/projects",
                data={
                    "name": "gitops",
                    "path": "gitops",
                    "namespace_id": gid,
                    "visibility": "private",
                    "default_branch": "main",
                    "initialize_with_readme": "false",
                    "description": "Index des services de l'équipe (ApplicationSet Argo CD)",
                },
            ).json()
            envs = ", ".join(e.get("environnements", {}))
            gl.appel(
                "POST",
                f"/projects/{p['id']}/repository/commits",
                json={
                    "branch": "main",
                    "commit_message": f"chore: index des services de l'équipe ({e['ticket']})",
                    "actions": [
                        {
                            "action": "create",
                            "file_path": "README.md",
                            "content": README_GITOPS.format(groupe=groupe_chemin, nom=e["nom"], envs=envs),
                        },
                        {"action": "create", "file_path": "services/.gitkeep", "content": ""},
                    ],
                },
            )

    if bao is None:
        journal.append(f"{e['nom']} : (aperçu sans OpenBao : jetons non contrôlés)")
        return

    # 3. Jeton de déploiement du groupe, pour Argo CD
    chemin_depot = f"plateforme/argocd/depot-{e['nom']}"
    jetons = [
        j
        for j in gl.appel("GET", f"/groups/{gid}/deploy_tokens").json()
        if j["name"] == "argocd-lecture" and not j.get("revoked") and not j.get("expired")
    ]
    if not jetons or expire_bientot(jetons[0].get("expires_at"), aujourdhui) or not bao_present(bao, chemin_depot):
        journal.append(f"{e['nom']} : (re)créer le jeton de déploiement argocd-lecture → kv/{chemin_depot}")
        if appliquer:
            fin = (aujourdhui + dt.timedelta(days=cfg["gitlab"]["jeton_deploiement_jours"])).isoformat()
            neuf = gl.appel(
                "POST",
                f"/groups/{gid}/deploy_tokens",
                json={
                    "name": "argocd-lecture",
                    "scopes": ["read_repository"],
                    "expires_at": fin,
                    "username": f"argocd-{e['nom']}",
                },
            ).json()
            bao_ecrire(
                bao,
                chemin_depot,
                {
                    "url": f"{cfg['gitlab']['url']}/{groupe_chemin}",
                    "username": neuf["username"],
                    "password": neuf["token"],
                },
            )
            for ancien in jetons:
                gl.appel("DELETE", f"/groups/{gid}/deploy_tokens/{ancien['id']}")

    # 4. Jeton d'accès de groupe pour la promotion (MR dans <groupe>/<service>-deploiement)
    chemin_promo = f"{e['nom']}/ci/promotion"
    jetons = [
        j for j in gl.appel("GET", f"/groups/{gid}/access_tokens").json() if j["name"] == "ci-promotion" and j.get("active")
    ]
    if not jetons or expire_bientot(jetons[0].get("expires_at"), aujourdhui) or not bao_present(bao, chemin_promo):
        journal.append(f"{e['nom']} : (re)créer le jeton de groupe ci-promotion → kv/{chemin_promo}")
        if appliquer:
            fin = (aujourdhui + dt.timedelta(days=cfg["gitlab"]["jeton_promotion_jours"])).isoformat()
            neuf = gl.appel(
                "POST",
                f"/groups/{gid}/access_tokens",
                json={
                    "name": "ci-promotion",
                    "scopes": ["api"],
                    "access_level": 30,
                    "expires_at": fin,
                },
            ).json()
            bao_ecrire(bao, chemin_promo, {"jeton": neuf["token"]})
            for ancien in jetons:
                gl.appel("DELETE", f"/groups/{gid}/access_tokens/{ancien['id']}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Groupes, projets et jetons GitLab des équipes (F2-S02).")
    parser.add_argument("--appliquer", action="store_true", help="applique (sinon : aperçu en lecture seule)")
    args = parser.parse_args()
    jeton = os.environ.get("GITLAB_EQUIPES_JETON", "")
    if not jeton:
        print("gitlab_equipes : GITLAB_EQUIPES_JETON absent", file=sys.stderr)
        return 2
    try:
        cfg, brutes = charger(RACINE)
        equipes = [normaliser(d) for d in brutes]
    except (OSError, Invalide) as err:
        print(f"gitlab_equipes : {err}", file=sys.stderr)
        return 1
    gl = Api(cfg["gitlab"]["url"] + "/api/v4", {"PRIVATE-TOKEN": jeton})
    bao = None
    if os.environ.get("BAO_TOKEN"):
        bao = Api(os.environ.get("BAO_ADDR", cfg["openbao"]["url"]), {"X-Vault-Token": os.environ["BAO_TOKEN"]})
    elif args.appliquer:
        print("gitlab_equipes : BAO_TOKEN absent : impossible de ranger les jetons", file=sys.stderr)
        return 2
    journal: list[str] = []
    try:
        for e in equipes:
            traiter(e, cfg, gl, bao, args.appliquer, journal)
    except (Erreur, requests.RequestException) as err:
        print(f"gitlab_equipes : {err}", file=sys.stderr)
        for ligne in journal:
            print(("FAIT     " if args.appliquer else "À FAIRE  ") + ligne)
        return 1
    for ligne in journal:
        print(("FAIT     " if args.appliquer else "À FAIRE  ") + ligne)
    print(
        f"gitlab_equipes : {len(equipes)} équipe(s), {len(journal)} action(s)"
        + (" appliquée(s)." if args.appliquer else " (aperçu, rien n'a été changé).")
    )
    return 3 if (journal and not args.appliquer) else 0


if __name__ == "__main__":
    sys.exit(main())
