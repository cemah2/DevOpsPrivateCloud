#!/usr/bin/env python3
"""plateforme/outils — bin/dora.py (M19-E28, PLAT-2028).

Calcule les quatre indicateurs DORA de MédiSphère pour un projet de DÉPLOIEMENT et un environnement,
sur une fenêtre glissante, à partir de l'API REST de GitLab (lecture seule, jeton read_api) :

  fréquence de déploiement   déploiements réussis / jour dans la fenêtre ;
  délai de mise en production  médiane (déploiement réussi − date du commit étiqueté de l'application) ;
                               chaîne : déploiement → commit de main du dépôt de déploiement → MR de
                               promotion (branche promotion/<env>-vX.Y.Z) → étiquette vX.Y.Z du projet
                               applicatif → date de son commit ;
  taux d'échec des changements (déploiements en échec + retours arrière) / déploiements tentés ;
                               retour arrière = déploiement d'une version inférieure à la précédente ;
  temps de rétablissement      médiane (fermeture − ouverture) des tickets étiquetés « incident » du
                               projet applicatif, ouverts dans la fenêtre.

Bibliothèque standard seulement. Le jeton est lu dans un fichier (jamais en argument).
Exemple :
  bin/dora.py --deploiement mediagenda/deploiement --application mediagenda/api --environnement dev
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import ssl
import statistics
import sys
import urllib.parse
import urllib.request

RE_PROMOTION = re.compile(r"^promotion/(?P<env>[a-z]+)-(?P<version>v\d+\.\d+\.\d+)$")


def date(s: str | None) -> dt.datetime | None:
    if not s:
        return None
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def version(v: str) -> tuple[int, ...]:
    return tuple(int(x) for x in v.lstrip("v").split("."))


class GitLab:
    def __init__(self, url: str, jeton: str, ca: str | None) -> None:
        self.url = url.rstrip("/") + "/api/v4/"
        self.jeton = jeton
        self.contexte = ssl.create_default_context(cafile=ca) if ca else ssl.create_default_context()

    def get(self, chemin: str, **params) -> object:
        requete = urllib.request.Request(
            self.url + chemin + ("?" + urllib.parse.urlencode(params) if params else ""),
            headers={"PRIVATE-TOKEN": self.jeton},
        )
        with urllib.request.urlopen(requete, context=self.contexte, timeout=30) as r:
            return json.load(r)

    def pages(self, chemin: str, **params) -> list:
        tout, page = [], 1
        while True:
            lot = self.get(chemin, per_page=100, page=page, **params)
            tout.extend(lot)
            if len(lot) < 100:
                return tout
            page += 1


def pid(chemin: str) -> str:
    return urllib.parse.quote(chemin, safe="")


def calculer(gl: GitLab, deploiement: str, application: str, env: str, jours: int,
             maintenant: dt.datetime | None = None) -> dict:
    maintenant = maintenant or dt.datetime.now(dt.timezone.utc)
    debut = maintenant - dt.timedelta(days=jours)
    deps = [d for d in gl.pages(f"projects/{pid(deploiement)}/deployments", environment=env,
                                 updated_after=debut.isoformat(), order_by="created_at", sort="asc")
            if d.get("status") in ("success", "failed")]

    reussis = [d for d in deps if d["status"] == "success"]
    echecs = [d for d in deps if d["status"] == "failed"]

    # Version déployée par chaque déploiement réussi (via la MR de promotion fusionnée).
    delais, versions = [], []
    for d in reussis:
        mrs = gl.get(f"projects/{pid(deploiement)}/repository/commits/{d['sha']}/merge_requests")
        m = next((RE_PROMOTION.match(mr["source_branch"]) for mr in mrs
                  if RE_PROMOTION.match(mr.get("source_branch", ""))), None)
        if not m:
            versions.append(None)          # changement de configuration seule : pas de version
            continue
        v = m["version"]
        versions.append(v)
        etiquette = gl.get(f"projects/{pid(application)}/repository/tags/{urllib.parse.quote(v, safe='')}")
        commit = date(etiquette["commit"]["committed_date"])
        fin = date(d.get("finished_at") or d.get("updated_at"))
        if commit and fin:
            delais.append((fin - commit).total_seconds() / 3600)

    retours = sum(1 for a, b in zip(versions, versions[1:]) if a and b and version(b) < version(a))

    incidents = gl.pages(f"projects/{pid(application)}/issues", labels="incident",
                         created_after=debut.isoformat(), state="all")
    retablissements = [(date(i["closed_at"]) - date(i["created_at"])).total_seconds() / 3600
                       for i in incidents if i.get("closed_at")]

    return {
        "fenetre_jours": jours,
        "deploiements_reussis": len(reussis),
        "frequence_par_jour": round(len(reussis) / jours, 2),
        "delai_median_h": round(statistics.median(delais), 1) if delais else None,
        "echecs": len(echecs),
        "retours_arriere": retours,
        "taux_echec": round((len(echecs) + retours) / len(deps), 3) if deps else None,
        "incidents": len(incidents),
        "incidents_ouverts": sum(1 for i in incidents if not i.get("closed_at")),
        "retablissement_median_h": round(statistics.median(retablissements), 1) if retablissements else None,
    }


def markdown(r: dict, deploiement: str, env: str) -> str:
    nd = "n. d."
    lignes = [
        f"Calcul du {dt.date.today().isoformat()} — `{deploiement}`, environnement `{env}`, {r['fenetre_jours']} jours glissants",
        "",
        "| Indicateur | Valeur | Base |",
        "|---|---|---|",
        f"| Fréquence de déploiement | {r['frequence_par_jour']} / jour | {r['deploiements_reussis']} déploiements réussis |",
        f"| Délai de mise en production (médiane) | {r['delai_median_h'] if r['delai_median_h'] is not None else nd} h | commit étiqueté → déploiement réussi |",
        f"| Taux d'échec des changements | {r['taux_echec'] if r['taux_echec'] is not None else nd} | {r['echecs']} échecs, {r['retours_arriere']} retours arrière |",
        f"| Temps de rétablissement (médiane) | {r['retablissement_median_h'] if r['retablissement_median_h'] is not None else nd} h | {r['incidents']} incidents, {r['incidents_ouverts']} encore ouverts |",
    ]
    return "\n".join(lignes)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--deploiement", required=True, help="projet de déploiement (ex. mediagenda/deploiement)")
    p.add_argument("--application", required=True, help="projet applicatif (ex. mediagenda/api)")
    p.add_argument("--environnement", default="dev")
    p.add_argument("--jours", type=int, default=30)
    p.add_argument("--json", action="store_true", help="sortie JSON au lieu de Markdown")
    a = p.parse_args(argv)

    fichier = os.environ.get("GITLAB_TOKEN_FILE", os.path.expanduser("~/.config/workbook/gitlab-checks.token"))
    with open(fichier, encoding="utf-8") as f:
        jeton = f.read().strip()
    gl = GitLab(os.environ.get("GITLAB_URL", "https://git01.par1.medisphere.internal"), jeton,
                os.environ.get("MEDISPHERE_ROOT_CA"))
    r = calculer(gl, a.deploiement, a.application, a.environnement, a.jours)
    print(json.dumps(r, indent=2) if a.json else markdown(r, a.deploiement, a.environnement))
    return 0


if __name__ == "__main__":
    sys.exit(main())
