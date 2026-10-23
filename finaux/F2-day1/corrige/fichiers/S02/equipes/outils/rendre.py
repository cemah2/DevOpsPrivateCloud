#!/usr/bin/env python3
"""rendre.py — valide les équipes décrites dans equipes/*.yaml et rend les fichiers des dépôts qui
appliquent (plateforme/equipes, F2-S02, PLAT-3202).

    uv run outils/rendre.py                 # valide, rend dans rendu/ (rien n'est envoyé nulle part)
    uv run outils/rendre.py --valider       # valide seulement (schéma + cohérence), code 1 si erreur
    uv run outils/rendre.py --sortie /tmp/r # autre dossier de sortie

Le rendu est COMPLET et DÉTERMINISTE : il contient toutes les équipes, dans le même ordre, à chaque
passage ; propager.py compare ce rendu aux chemins possédés dans chaque dépôt cible (config/plateforme.yaml)
et en déduit les créations, modifications et suppressions. Aucun secret n'est lu ni écrit ici.

Dépôts cibles et fichiers rendus :
  identite/  annuaire/equipes/personnes.yml, annuaire/equipes/groupes.yml   (Ansible, freeipa.ansible_freeipa)
             outils/synchro-gitlab.d/equipes.yml                          (synchro-gitlab.py, M24-E11)
             tofu/equipes.auto.tfvars.json                                 (OTP : flux.tf, M24-E21)
  secrets/   tofu/equipes.auto.tfvars.json                                 (equipes.tf : politiques, groupes, rôles)
  grafana/   observabilite-grafana/equipes.auto.tfvars.json                (dossier et équipe Grafana)
  k8s/       equipes/<equipe>/{locataire,isolement}.yaml, equipes/<equipe>/espaces/<espace>.yaml
  gitops/    equipes/<equipe>/{projet,services,depot}.yaml, valeurs/capsule/utilisateurs-equipes.yaml

Codes : 0 rendu fait ; 1 données invalides ; 2 usage.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from decimal import Decimal
from pathlib import Path

import jinja2
import yaml
from jsonschema import Draft202012Validator, FormatChecker

RACINE = Path(__file__).resolve().parent.parent
ENTETE_YAML = "# GÉNÉRÉ par plateforme/equipes (outils/rendre.py) — NE PAS MODIFIER ICI : MR sur plateforme/equipes.\n"

NIVEAU_GITLAB = {"responsable": "maintainer", "developpeur": "developer", "lecteur": "reporter"}

# Facteurs des suffixes de quantités Kubernetes utilisés dans les quotas.
SUFFIXES = {
    "m": Decimal("0.001"),
    "Ki": Decimal(1024),
    "Mi": Decimal(1024) ** 2,
    "Gi": Decimal(1024) ** 3,
    "Ti": Decimal(1024) ** 4,
    "": Decimal(1),
}


class Invalide(Exception):
    """Données d'équipe refusées (message destiné à l'auteur de la MR)."""


def quantite(valeur: str | int) -> Decimal:
    """« 500m » → 0.5 ; « 3Gi » → 3221225472 ; « 2 » → 2."""
    m = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)(m|Ki|Mi|Gi|Ti)?", str(valeur))
    if not m:
        raise Invalide(f"quantité illisible : {valeur!r}")
    return Decimal(m.group(1)) * SUFFIXES[m.group(2) or ""]


def lire_yaml(chemin: Path) -> dict:
    with chemin.open(encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def charger(racine: Path) -> tuple[dict, list[dict]]:
    config = lire_yaml(racine / "config/plateforme.yaml")
    schema = json.loads((racine / "schema/equipe.schema.json").read_text(encoding="utf-8"))
    validateur = Draft202012Validator(schema, format_checker=FormatChecker())
    equipes, erreurs = [], []
    for fichier in sorted((racine / "equipes").glob("*.yaml")):
        donnees = lire_yaml(fichier)
        for err in sorted(validateur.iter_errors(donnees), key=lambda e: list(e.path)):
            chemin = "/".join(str(p) for p in err.path) or "(racine)"
            erreurs.append(f"{fichier.name} : {chemin} : {err.message}")
        if donnees.get("metadata", {}).get("nom") != fichier.stem:
            erreurs.append(f"{fichier.name} : metadata.nom doit valoir « {fichier.stem} » (nom du fichier)")
        equipes.append(donnees)
    if erreurs:
        raise Invalide("\n".join(erreurs))
    return config, equipes


def normaliser(d: dict) -> dict:
    """Vue à plat d'une équipe, avec les valeurs par défaut, pour les gabarits et les contrôles."""
    s = d["spec"]
    k = s.get("kubernetes")
    e = {
        "nom": d["metadata"]["nom"],
        "ticket": d["metadata"]["ticket"],
        "description": s["description"],
        "type": s["type"],
        "etat": s["etat"],
        "responsable": s["responsable"],
        "contact": s["contact"],
        "expiration": s.get("expiration"),
        "personnes": s["personnes"],
        "otp": s["identite"]["otp_obligatoire"],
        "groupe_gitlab": s["gitlab"]["groupe"],
        "externe": s["gitlab"].get("externe", False),
        "services": s.get("services", []),
        "ecriture": (s.get("secrets") or {}).get("ecriture", []),
        "titre_dossier": ((s.get("observabilite") or {}).get("grafana") or {}).get("titre_dossier", d["metadata"]["nom"]),
        "kubernetes": k is not None,
    }
    if k:
        e["environnements"] = k["environnements"]
        e["environnements_manuels"] = [n for n, c in k["environnements"].items() if c["synchronisation"] == "manuelle"]
        e["libre_service"] = k.get("libre_service") or {
            "espaces": 0,
            "quota": {"requests.cpu": "0", "requests.memory": "0", "limits.memory": "0", "pods": "0"},
        }
        e["budget"] = k["budget"]
        e["classes_priorite"] = k["classes_priorite"]
        e["classes_stockage"] = k["classes_stockage"]
    return e


def controler(config: dict, equipes: list[dict]) -> None:
    """Règles que le schéma ne sait pas exprimer. Lève Invalide avec TOUTES les erreurs trouvées."""
    erreurs: list[str] = []
    reserves = set(config.get("noms_reserves", []))
    vues: dict[str, tuple[str, dict]] = {}
    for e in equipes:
        n = e["nom"]
        if n in reserves:
            erreurs.append(f"{n} : nom réservé (groupe ou préfixe d'espace déjà utilisé)")
        for autre in (x["nom"] for x in equipes if x["nom"] != n):
            if autre.startswith(n + "-"):
                erreurs.append(f"{n} : préfixe de l'équipe {autre} (les espaces {autre}-… seraient ambigus)")
        idents = [p["identifiant"] for p in e["personnes"]]
        if len(set(idents)) != len(idents):
            erreurs.append(f"{n} : identifiant en double dans personnes")
        if e["responsable"] not in idents:
            erreurs.append(f"{n} : le responsable {e['responsable']} n'est pas dans personnes")
        for p in e["personnes"]:
            if any("<" in str(v) for v in p.values()):
                erreurs.append(f"{n} : valeur <À-ADAPTER> restée telle quelle ({p['identifiant']})")
            # Une même personne dans deux équipes : autorisé, mais décrite à l'identique.
            fiche = {c: p.get(c) for c in ("prenom", "nom", "courriel")}
            if p["identifiant"] in vues and vues[p["identifiant"]][1] != fiche:
                erreurs.append(f"{n} : {p['identifiant']} décrit autrement dans {vues[p['identifiant']][0]}")
            vues.setdefault(p["identifiant"], (n, fiche))
        if e["type"] == "prestataire" and e["kubernetes"] and e["environnements_manuels"]:
            erreurs.append(f"{n} : un prestataire n'a pas d'environnement de production")
        if not e["kubernetes"]:
            if e["ecriture"] or e["services"]:
                erreurs.append(f"{n} : secrets.ecriture et services exigent un bloc kubernetes")
            continue
        envs = set(e["environnements"])
        hors = set(e["ecriture"]) - envs
        if hors:
            erreurs.append(f"{n} : secrets.ecriture cite des environnements inconnus : {', '.join(sorted(hors))}")
        for env in envs:
            if env == "ci":
                erreurs.append(f"{n} : « ci » est réservé (kv/{n}/ci/ porte les jetons de la CI, jamais lisibles par l'équipe)")
            if len(f"{n}-{env}") > 63:
                erreurs.append(f"{n} : espace {n}-{env} trop long (63 caractères au plus)")
        cp = e["classes_priorite"]
        if cp["defaut"] not in cp["autorisees"]:
            erreurs.append(f"{n} : classe de priorité par défaut absente des classes autorisées")
        if e["environnements_manuels"] and "medisphere-critique" not in cp["autorisees"]:
            erreurs.append(f"{n} : une production (synchronisation manuelle) exige medisphere-critique")
        # Les quotas d'espace et le libre-service doivent tenir dans le budget du locataire.
        for ressource, plafond in e["budget"].items():
            somme = sum((quantite(c["quota"].get(ressource, 0)) for c in e["environnements"].values()), Decimal(0))
            somme += quantite(e["libre_service"]["quota"].get(ressource, 0))
            if somme > quantite(plafond):
                erreurs.append(f"{n} : {ressource} — environnements + libre-service ({somme}) dépassent le budget ({plafond})")
    if erreurs:
        raise Invalide("\n".join(erreurs))


# --------------------------------------------------------------------------------------------------
# Rendus par dépôt
# --------------------------------------------------------------------------------------------------


def ecrire(sortie: Path, chemin: str, contenu: str) -> None:
    f = sortie / chemin
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(contenu, encoding="utf-8")


def yaml_texte(donnees: dict) -> str:
    return ENTETE_YAML + yaml.safe_dump(donnees, allow_unicode=True, sort_keys=False, width=120)


def json_texte(donnees: dict) -> str:
    return json.dumps(donnees, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def rendre_identite(equipes: list[dict], sortie: Path) -> None:
    personnes: dict[str, dict] = {}
    groupes, lignes = [], []
    for e in equipes:
        active = e["etat"] == "active"
        for p in e["personnes"]:
            fiche = {
                "identifiant": p["identifiant"],
                "prenom": p["prenom"],
                "nom": p["nom"],
                "courriel": p["courriel"],
                "titre": p.get("titre", ""),
                # Équipe retirée : tout le monde est désactivé (jamais supprimé, RB-242).
                "etat": p.get("etat", "present") if active else "disabled",
            }
            expiration = p.get("expiration") or e["expiration"]
            if expiration:
                fiche["expiration"] = expiration
            # Une personne de deux équipes : désactivée seulement si elle l'est partout.
            if p["identifiant"] in personnes and fiche["etat"] == "disabled":
                continue
            personnes[p["identifiant"]] = fiche
        membres = [p["identifiant"] for p in e["personnes"] if active and p.get("etat", "present") == "present"]
        groupes.append({"nom": e["nom"], "description": e["description"], "membres": membres})
        lignes.append({"annuaire": e["nom"], "gitlab": e["groupe_gitlab"], "niveau": "reporter"})
        for p in e["personnes"]:
            if active and p.get("etat", "present") == "present" and p["role"] != "lecteur":
                lignes.append({"personne": p["identifiant"], "gitlab": e["groupe_gitlab"], "niveau": NIVEAU_GITLAB[p["role"]]})
    ecrire(
        sortie, "identite/annuaire/equipes/personnes.yml", yaml_texte({"annuaire_personnes_equipes": list(personnes.values())})
    )
    ecrire(sortie, "identite/annuaire/equipes/groupes.yml", yaml_texte({"annuaire_groupes_equipes": groupes}))
    ecrire(sortie, "identite/outils/synchro-gitlab.d/equipes.yml", yaml_texte({"synchro_gitlab": lignes}))
    ecrire(
        sortie,
        "identite/tofu/equipes.auto.tfvars.json",
        json_texte(
            {
                "groupes_otp_equipes": sorted(e["nom"] for e in equipes if e["otp"] and e["etat"] == "active"),
            }
        ),
    )


def rendre_secrets(equipes: list[dict], sortie: Path) -> None:
    donnees = {}
    for e in equipes:
        if e["etat"] != "active" or not e["kubernetes"]:
            continue
        donnees[e["nom"]] = {
            "groupe_gitlab": e["groupe_gitlab"],
            "environnements": sorted(e["environnements"]),
            "ecriture": sorted(e["ecriture"]),
            "services": sorted(e["services"]),
        }
    ecrire(sortie, "secrets/tofu/equipes.auto.tfvars.json", json_texte({"equipes_en_code": donnees}))


def rendre_grafana(equipes: list[dict], sortie: Path) -> None:
    donnees = {}
    for e in equipes:
        if e["etat"] != "active":
            continue
        actives = [p for p in e["personnes"] if p.get("etat", "present") == "present"]
        donnees[e["nom"]] = {
            "titre_dossier": e["titre_dossier"],
            "membres": sorted(p["courriel"] for p in actives if p["role"] != "responsable"),
            "admins": sorted(p["courriel"] for p in actives if p["role"] == "responsable"),
        }
    ecrire(sortie, "grafana/observabilite-grafana/equipes.auto.tfvars.json", json_texte({"equipes_en_code": donnees}))


def rendre_k8s_gitops(config: dict, equipes: list[dict], sortie: Path) -> None:
    env_j2 = jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(RACINE / "gabarits")),
        undefined=jinja2.StrictUndefined,
        keep_trailing_newline=True,
        trim_blocks=False,
        lstrip_blocks=False,
    )
    racine_b64 = config["openbao"]["racine_base64"]
    utilisateurs = list(config.get("capsule_utilisateurs_existants", []))
    for e in equipes:
        # Équipe retirée ou sans locataire : rien dans k8s ni gitops. Les objets déjà créés (Tenant,
        # espaces) portent Prune=false : leur retrait est un geste explicite (RB-320 § Départ).
        if e["etat"] != "active" or not e["kubernetes"]:
            continue
        utilisateurs.append(f"oidc:{e['nom']}")
        base = f"k8s/equipes/{e['nom']}"
        ecrire(sortie, f"{base}/locataire.yaml", env_j2.get_template("k8s/locataire.yaml.j2").render(e=e))
        ecrire(sortie, f"{base}/isolement.yaml", env_j2.get_template("k8s/isolement.yaml.j2").render(e=e))
        for env, c in e["environnements"].items():
            ns = f"{e['nom']}-{env}"
            ecrire(
                sortie,
                f"{base}/espaces/{ns}.yaml",
                env_j2.get_template("k8s/espace.yaml.j2").render(
                    e=e, env=env, c=c, ns=ns, racine=racine_b64, openbao_url=config["openbao"]["url"]
                ),
            )
        g = f"gitops/equipes/{e['nom']}"
        ecrire(sortie, f"{g}/projet.yaml", env_j2.get_template("gitops/projet.yaml.j2").render(e=e))
        ecrire(sortie, f"{g}/services.yaml", env_j2.get_template("gitops/applicationset.yaml.j2").render(e=e))
        ecrire(sortie, f"{g}/depot.yaml", env_j2.get_template("gitops/depot.yaml.j2").render(e=e))
    ecrire(
        sortie,
        "gitops/valeurs/capsule/utilisateurs-equipes.yaml",
        env_j2.get_template("gitops/capsule-utilisateurs.yaml.j2").render(utilisateurs=utilisateurs),
    )


def verifier_rendu(sortie: Path) -> None:
    """Tout fichier YAML/JSON rendu doit se relire (garde-fou contre un gabarit cassé)."""
    for f in sorted(sortie.rglob("*")):
        if f.suffix in (".yaml", ".yml"):
            list(yaml.safe_load_all(f.read_text(encoding="utf-8")))
        elif f.suffix == ".json":
            json.loads(f.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Valide les équipes et rend les fichiers des dépôts cibles (F2-S02).")
    parser.add_argument("--valider", action="store_true", help="valide seulement")
    parser.add_argument("--racine", type=Path, default=RACINE)
    parser.add_argument("--sortie", type=Path, default=RACINE / "rendu")
    args = parser.parse_args()
    try:
        config, brutes = charger(args.racine)
        equipes = [normaliser(d) for d in brutes]
        controler(config, equipes)
    except (OSError, yaml.YAMLError, json.JSONDecodeError, Invalide) as err:
        print(f"rendre : données refusées\n{err}", file=sys.stderr)
        return 1
    print(f"rendre : {len(equipes)} équipe(s) valides : {', '.join(e['nom'] for e in equipes)}")
    if args.valider:
        return 0
    if args.sortie.exists():
        shutil.rmtree(args.sortie)
    rendre_identite(equipes, args.sortie)
    rendre_secrets(equipes, args.sortie)
    rendre_grafana(equipes, args.sortie)
    rendre_k8s_gitops(config, equipes, args.sortie)
    try:
        verifier_rendu(args.sortie)
    except (yaml.YAMLError, json.JSONDecodeError) as err:
        print(f"rendre : un gabarit produit un fichier illisible : {err}", file=sys.stderr)
        return 1
    n = sum(1 for f in args.sortie.rglob("*") if f.is_file())
    print(f"rendre : {n} fichier(s) dans {args.sortie}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
