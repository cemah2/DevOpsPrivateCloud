#!/usr/bin/env python3
"""Revue mensuelle des accès de MédiSphère (M24-E30, SEC-2530).

Croise, en LECTURE SEULE et avec des identités dédiées, l'annuaire (FreeIPA), Keycloak (royaume
medisphere), GitLab, Grafana, Argo CD, Proxmox VE et le RBAC de Kubernetes ; compare au modèle
d'autorisation (modele.yml, traduction de M24-E10) ; produit un rapport Markdown (pour la RSSI) et
JSON (pour comparer deux mois), l'envoie par courriel et, en CI, ouvre une MR sur plateforme/medisphere.

Usage :
  uv run revue_acces.py --sortie rapport [--precedent ANCIEN.json] [--envoyer] [--mr]

Configuration : variables d'environnement REVUE_* (voir README.md). Aucun secret n'est écrit ni
affiché ; le rapport ne contient que des identifiants, des groupes et des droits.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import smtplib
import ssl
import sys
from dataclasses import dataclass, field
from email.message import EmailMessage
from pathlib import Path
from urllib.parse import quote

import requests
import yaml
from ldap3 import SUBTREE, Connection, Server, Tls

ICI = Path(__file__).resolve().parent
DELAI = 15


def env(nom: str, defaut: str | None = None) -> str:
    """Lit une variable d'environnement obligatoire (sans jamais l'afficher)."""
    valeur = os.environ.get(nom, defaut)
    if valeur is None or valeur == "":
        sys.exit(f"revue-acces : variable {nom} absente")
    return valeur


RACINE = os.environ.get("REVUE_RACINE", "/usr/local/share/ca-certificates/medisphere-root-ca.crt")


def http_get(url: str, **kwargs) -> requests.Response:
    reponse = requests.get(url, timeout=DELAI, verify=RACINE, **kwargs)
    reponse.raise_for_status()
    return reponse


@dataclass
class Ecart:
    """Un écart : quelque chose qui n'est pas ce que le modèle dit, avec une clé stable."""

    type: str
    service: str
    sujet: str
    detail: str
    accepte: str = ""

    @property
    def cle(self) -> str:
        return f"{self.type}:{self.service}:{self.sujet}"


@dataclass
class Revue:
    date: str
    personnes: dict = field(default_factory=dict)  # identifiant -> {etat, groupes, acces: {service: droit}}
    comptes_hors_sso: list = field(default_factory=list)  # {service, compte, raison}
    ecarts: list[Ecart] = field(default_factory=list)


# --- Sources ----------------------------------------------------------------------------------------


def lire_annuaire() -> dict:
    """Personnes de l'annuaire : état (actif/désactivé) et groupes de personnes."""
    tls = Tls(ca_certs_file=RACINE, validate=ssl.CERT_REQUIRED)
    serveur = Server(env("REVUE_LDAP_URL", "ldaps://ipa01.par1.medisphere.internal"), use_ssl=True, tls=tls)
    base = env("REVUE_LDAP_BASE", "dc=par1,dc=medisphere,dc=internal")
    with Connection(serveur, user=env("REVUE_LDAP_DN"), password=env("REVUE_LDAP_MOT_DE_PASSE"), auto_bind=True) as cnx:
        cnx.search(f"cn=users,cn=accounts,{base}", "(&(objectClass=person)(!(uid=admin)))", SUBTREE,
                   attributes=["uid", "nsAccountLock", "memberOf"])
        personnes = {}
        for entree in cnx.entries:
            groupes = sorted(
                dn.split(",")[0].removeprefix("cn=")
                for dn in (entree.memberOf.values if "memberOf" in entree else [])
                if f",cn=groups,cn=accounts,{base}" in dn
            )
            verrou = str(entree.nsAccountLock.value).upper() if "nsAccountLock" in entree else "FALSE"
            personnes[str(entree.uid)] = {"etat": "désactivé" if verrou == "TRUE" else "actif", "groupes": groupes, "acces": {}}
    return personnes


def jeton_keycloak() -> str:
    base = env("REVUE_KEYCLOAK_URL", "https://sso.par1.medisphere.internal")
    reponse = requests.post(
        f"{base}/realms/medisphere/protocol/openid-connect/token",
        data={"grant_type": "client_credentials"},
        auth=(env("REVUE_KEYCLOAK_CLIENT_ID", "revue-acces"), env("REVUE_KEYCLOAK_CLIENT_SECRET")),
        timeout=DELAI, verify=RACINE,
    )
    reponse.raise_for_status()
    return reponse.json()["access_token"]


def lire_keycloak() -> dict:
    """Personnes connues de Keycloak (royaume medisphere) : actives ? liées à l'annuaire ?"""
    base = env("REVUE_KEYCLOAK_URL", "https://sso.par1.medisphere.internal")
    entetes = {"Authorization": f"Bearer {jeton_keycloak()}"}
    utilisateurs = http_get(f"{base}/admin/realms/medisphere/users?briefRepresentation=false&max=1000", headers=entetes).json()
    return {
        u["username"]: {"actif": u.get("enabled", False), "federe": bool(u.get("federationLink")),
                        "compte_de_service": u["username"].startswith("service-account-")}
        for u in utilisateurs
    }


def lire_gitlab() -> tuple[dict, list]:
    """Utilisateurs GitLab (actifs, administrateurs, identité OIDC) et jetons personnels actifs."""
    base = env("REVUE_GITLAB_URL", "https://git01.par1.medisphere.internal") + "/api/v4"
    entetes = {"PRIVATE-TOKEN": env("REVUE_GITLAB_TOKEN")}
    utilisateurs, noms, page = {}, {}, 1
    while True:
        lot = http_get(f"{base}/users?active=true&per_page=100&page={page}", headers=entetes).json()
        for u in lot:
            fournisseurs = [i.get("provider") for i in u.get("identities", [])]
            noms[u["id"]] = u["username"]
            utilisateurs[u["username"]] = {"admin": u.get("is_admin", False), "oidc": "openid_connect" in fournisseurs,
                                           "bot": u.get("bot", False)}
        if len(lot) < 100:
            break
        page += 1
    jetons = http_get(f"{base}/personal_access_tokens?state=active&per_page=100", headers=entetes).json()
    return utilisateurs, [{"proprietaire": noms.get(j.get("user_id"), f"id-{j.get('user_id')}"), "nom": j.get("name"),
                           "expire": j.get("expires_at")} for j in jetons]


def lire_grafana() -> dict:
    """Utilisateurs de l'organisation principale : rôle, et origine (SSO ou local) par authLabels."""
    base = env("REVUE_GRAFANA_URL", "https://grafana.apps.par1.medisphere.internal")
    utilisateurs = http_get(f"{base}/api/org/users", headers={"Authorization": f"Bearer {env('REVUE_GRAFANA_TOKEN')}"}).json()
    return {u["login"]: {"role": u.get("role"), "sso": "Generic OAuth" in (u.get("authLabels") or [])} for u in utilisateurs}


def k8s_get(chemin: str) -> dict:
    api = env("REVUE_K8S_API", "https://10.10.40.200:8443")
    reponse = requests.get(f"{api}{chemin}", headers={"Authorization": f"Bearer {env('REVUE_K8S_TOKEN')}"},
                           timeout=DELAI, verify=env("REVUE_K8S_CA"))
    reponse.raise_for_status()
    return reponse.json()


def lire_kubernetes() -> list:
    """Sujets User et Group des liaisons RBAC (les comptes de service sont des programmes)."""
    sujets = []
    for chemin in ("/apis/rbac.authorization.k8s.io/v1/clusterrolebindings", "/apis/rbac.authorization.k8s.io/v1/rolebindings"):
        for liaison in k8s_get(chemin).get("items", []):
            for s in liaison.get("subjects") or []:
                if s.get("kind") in ("User", "Group"):
                    sujets.append({"sujet": s["name"], "role": liaison["roleRef"]["name"],
                                   "espace": liaison["metadata"].get("namespace", "(cluster)"),
                                   "liaison": liaison["metadata"]["name"]})
    return sujets


def lire_argocd() -> dict:
    """Comptes locaux d'Argo CD (argocd-cm) et règles de groupes (argocd-rbac-cm)."""
    cm = k8s_get("/api/v1/namespaces/argocd/configmaps/argocd-cm").get("data", {})
    rbac = k8s_get("/api/v1/namespaces/argocd/configmaps/argocd-rbac-cm").get("data", {})
    comptes = {cle.split(".", 1)[1]: valeur for cle, valeur in cm.items() if cle.startswith("accounts.") and cle.count(".") == 1}
    if cm.get("admin.enabled", "true") != "false":
        comptes["admin"] = "login (actif)"
    groupes = {}
    for ligne in rbac.get("policy.csv", "").splitlines():
        champs = [c.strip() for c in ligne.split(",")]
        if len(champs) == 3 and champs[0] == "g":
            groupes[champs[1]] = champs[2]
    return {"comptes": comptes, "groupes": groupes, "defaut": rbac.get("policy.default", "")}


def lire_proxmox() -> dict:
    base = env("REVUE_PVE_URL", "https://pve01.par1.medisphere.internal:8006") + "/api2/json"
    entetes = {"Authorization": f"PVEAPIToken={env('REVUE_PVE_TOKEN')}"}
    utilisateurs = http_get(f"{base}/access/users", headers=entetes).json()["data"]
    return {u["userid"]: {"actif": bool(u.get("enable", 1))} for u in utilisateurs}


# --- Analyse ------------------------------------------------------------------------------------------


def analyser(modele: dict, sources: dict) -> Revue:
    revue = Revue(date=dt.date.today().isoformat(), personnes=sources["annuaire"])
    personnes = revue.personnes
    groupes_connus = set(modele["groupes_personnes"])

    # Grafana : rôle effectif et origine ; tout compte local hors liste est un écart.
    attendus = modele["services"]["grafana"]
    for login, g in sources["grafana"].items():
        if login in personnes:
            personnes[login]["acces"]["grafana"] = g["role"]
            if personnes[login]["etat"] != "actif":
                revue.ecarts.append(Ecart("acces-personne-desactivee", "grafana", login, f"rôle {g['role']}"))
            attendu = max((attendus["droits"].get(gr, "") for gr in personnes[login]["groupes"]),
                          key=["", "Viewer", "Editor", "Admin"].index, default="")
            if attendu and g["role"] != attendu:
                revue.ecarts.append(Ecart("droit-hors-modele", "grafana", login, f"{g['role']} au lieu de {attendu}"))
        if not g["sso"]:
            raison = attendus["comptes_hors_sso"].get(login)
            revue.comptes_hors_sso.append({"service": "grafana", "compte": login, "raison": raison or "INCONNU"})
            if not raison:
                revue.ecarts.append(Ecart("compte-local-inconnu", "grafana", login, f"compte local, rôle {g['role']}"))

    # GitLab : personnes, administrateurs, comptes hors SSO, jetons.
    attendus = modele["services"]["gitlab"]
    utilisateurs, jetons = sources["gitlab"]
    for login, u in utilisateurs.items():
        if login in personnes:
            personnes[login]["acces"]["gitlab"] = "administrateur" if u["admin"] else "utilisateur"
            if personnes[login]["etat"] != "actif":
                revue.ecarts.append(Ecart("acces-personne-desactivee", "gitlab", login, "compte GitLab actif"))
        elif not u["bot"]:
            raison = attendus["comptes_hors_sso"].get(login)
            revue.comptes_hors_sso.append({"service": "gitlab", "compte": login, "raison": raison or "INCONNU"})
            if not raison:
                revue.ecarts.append(Ecart("compte-local-inconnu", "gitlab", login, "compte actif hors annuaire"))
        if u["admin"] and login not in attendus["administrateurs"] and not (
                login in personnes and "plateforme-admins" in personnes[login]["groupes"]):
            revue.ecarts.append(Ecart("administrateur-hors-modele", "gitlab", login, "administrateur GitLab"))
    for j in jetons:
        if not j["expire"]:
            revue.ecarts.append(Ecart("jeton-sans-expiration", "gitlab", str(j["proprietaire"]), f"jeton « {j['nom']} »"))

    # Argo CD : comptes locaux attendus, groupes de policy.csv connus, politique par défaut.
    argo, attendus = sources["argocd"], modele["services"]["argocd"]
    for compte in argo["comptes"]:
        raison = attendus["comptes_hors_sso"].get(compte)
        revue.comptes_hors_sso.append({"service": "argocd", "compte": compte, "raison": raison or "INCONNU"})
        if not raison:
            revue.ecarts.append(Ecart("compte-local-inconnu", "argocd", compte, "compte local d'Argo CD"))
    for groupe, role in argo["groupes"].items():
        if attendus["droits"].get(groupe) != role:
            attendu = attendus["droits"].get(groupe, "aucun")
            revue.ecarts.append(Ecart("droit-hors-modele", "argocd", groupe, f"{role} (attendu : {attendu})"))
    if argo["defaut"] not in ("", "role:readonly"):
        revue.ecarts.append(Ecart("droit-hors-modele", "argocd", "policy.default", argo["defaut"]))
    for p in personnes.values():
        droits = [argo["groupes"][g] for g in p["groupes"] if g in argo["groupes"]]
        if droits:
            p["acces"]["argocd"] = ", ".join(sorted(set(droits)))

    # Kubernetes : tout sujet hors « oidc: », hors system:* et hors liste attendue est un écart.
    attendus = modele["services"]["kubernetes"]["sujets_hors_oidc_attendus"]
    for s in sources["kubernetes"]:
        nom = s["sujet"]
        if nom.startswith("oidc:"):
            groupe = nom.removeprefix("oidc:")
            if groupe not in groupes_connus:
                revue.ecarts.append(Ecart("groupe-inconnu", "kubernetes", nom, f"{s['role']} ({s['espace']})"))
            for p in personnes.values():
                if groupe in p["groupes"]:
                    p["acces"].setdefault("kubernetes", set()).add(f"{s['role']}@{s['espace']}")
        elif nom.startswith("system:") and nom != "system:masters":
            continue
        elif nom in attendus:
            revue.comptes_hors_sso.append({"service": "kubernetes", "compte": nom, "raison": attendus[nom]})
        else:
            revue.ecarts.append(Ecart("liaison-hors-oidc", "kubernetes", nom, f"{s['role']} ({s['espace']}, {s['liaison']})"))
    for p in personnes.values():
        if isinstance(p["acces"].get("kubernetes"), set):
            p["acces"]["kubernetes"] = ", ".join(sorted(p["acces"]["kubernetes"]))

    # Proxmox : tout utilisateur hors royaume SSO et hors liste est un écart.
    attendus = modele["services"]["proxmox"]
    for userid, u in sources["proxmox"].items():
        nom, _, royaume = userid.partition("@")
        if royaume == attendus["royaume_sso"]:
            if nom in personnes:
                personnes[nom]["acces"]["proxmox"] = "royaume medisphere"
                if personnes[nom]["etat"] != "actif" and u["actif"]:
                    revue.ecarts.append(Ecart("acces-personne-desactivee", "proxmox", userid, "utilisateur Proxmox actif"))
            continue
        raison = attendus["comptes_hors_sso"].get(userid)
        revue.comptes_hors_sso.append({"service": "proxmox", "compte": userid, "raison": raison or "INCONNU"})
        if not raison and u["actif"]:
            revue.ecarts.append(Ecart("compte-local-inconnu", "proxmox", userid, "utilisateur Proxmox hors SSO"))

    # Keycloak : toute personne connue de Keycloak doit venir de l'annuaire.
    for login, k in sources["keycloak"].items():
        if k["compte_de_service"]:
            continue
        if not k["federe"]:
            revue.ecarts.append(Ecart("compte-local-inconnu", "keycloak", login, "utilisateur local du royaume medisphere"))
        elif login in personnes and personnes[login]["etat"] != "actif" and k["actif"]:
            revue.ecarts.append(Ecart("acces-personne-desactivee", "keycloak", login, "encore actif dans Keycloak (synchronisation ?)"))
    return revue


def appliquer_acceptes(revue: Revue, acceptes: list, aujourd_hui: dt.date) -> None:
    index = {a["cle"]: a for a in acceptes}
    for e in revue.ecarts:
        a = index.get(e.cle)
        if a and dt.date.fromisoformat(str(a["jusqu_au"])) >= aujourd_hui:
            e.accepte = f"accepté par {a['accepte_par']} jusqu'au {a['jusqu_au']} : {a['raison']}"


def comparer(revue: Revue, precedent: dict | None) -> dict:
    if not precedent:
        return {"nouveaux": [e.cle for e in revue.ecarts if not e.accepte], "resolus": []}
    avant = set(precedent.get("ecarts", {}).keys())
    maintenant = {e.cle for e in revue.ecarts}
    return {"nouveaux": sorted(maintenant - avant), "resolus": sorted(avant - maintenant)}


# --- Rendus -------------------------------------------------------------------------------------------


def rendre_json(revue: Revue) -> dict:
    return {
        "date": revue.date,
        "personnes": revue.personnes,
        "comptes_hors_sso": revue.comptes_hors_sso,
        "ecarts": {e.cle: {"detail": e.detail, "accepte": e.accepte} for e in revue.ecarts},
    }


def rendre_markdown(revue: Revue, diff: dict) -> str:
    services = ["gitlab", "grafana", "argocd", "kubernetes", "proxmox"]
    lignes = [f"# Revue des accès — {revue.date}", "",
              "Produit par `plateforme/identite/outils/revue-acces` (M24-E30). Sources : annuaire, Keycloak, GitLab, "
              "Grafana, Argo CD, Proxmox VE, RBAC de `k8s-par1`. Signature : approbation de la MR par la RSSI.", "",
              "## Écarts", ""]
    ouverts = [e for e in revue.ecarts if not e.accepte]
    if ouverts:
        lignes += ["| Nouveau ? | Clé | Détail |", "|---|---|---|"]
        lignes += [f"| {'**oui**' if e.cle in diff['nouveaux'] else 'non'} | `{e.cle}` | {e.detail} |" for e in ouverts]
    else:
        lignes.append("Aucun écart ouvert.")
    acceptes = [e for e in revue.ecarts if e.accepte]
    if acceptes:
        lignes += ["", "**Écarts acceptés** (`ecarts-acceptes.yml`) :", ""]
        lignes += [f"- `{e.cle}` — {e.accepte}" for e in acceptes]
    if diff["resolus"]:
        lignes += ["", "**Résolus depuis la revue précédente** : " + ", ".join(f"`{c}`" for c in diff["resolus"])]
    lignes += ["", "## Personnes de l'annuaire et accès effectifs", "",
               "| Personne | État | Groupes | " + " | ".join(services) + " |",
               "|---|---|---|" + "---|" * len(services)]
    for login in sorted(revue.personnes):
        p = revue.personnes[login]
        lignes.append(f"| `{login}` | {p['etat']} | {', '.join(p['groupes']) or '—'} | "
                      + " | ".join(str(p["acces"].get(s, "—")) for s in services) + " |")
    lignes += ["", "## Comptes hors SSO (locaux, de service, de secours)", "",
               "| Service | Compte | Justification |", "|---|---|---|"]
    lignes += [f"| {c['service']} | `{c['compte']}` | {c['raison']} |" for c in revue.comptes_hors_sso]
    lignes += ["", "## Ce que cette revue ne voit pas", "",
               "Administrateurs du royaume `master` de Keycloak (contrôlés par RB-240 et `lab/bin/check 24 04`), "
               "organisation « Sécurité » de Grafana, Harbor, NetBox, PBS, règles HBAC et sudo, comptes locaux des VMs : "
               "voir `outils/revue-acces/README.md`.", ""]
    return "\n".join(lignes)


def envoyer(sujet: str, corps: str, piece: Path) -> None:
    message = EmailMessage()
    message["From"] = env("REVUE_EXPEDITEUR", "revue-acces@medisphere.internal")
    message["To"] = env("REVUE_DESTINATAIRE", "securite@medisphere.internal")
    message["Subject"] = sujet
    message.set_content(corps)
    message.add_attachment(piece.read_bytes(), maintype="text", subtype="markdown", filename=piece.name)
    with smtplib.SMTP(env("REVUE_SMTP", "smtp.par1.medisphere.internal"), 25, timeout=DELAI) as smtp:
        smtp.starttls(context=ssl.create_default_context(cafile=RACINE))
        smtp.send_message(message)


def publier_mr(md: Path, js: Path, mois: str) -> str:
    """Branche, fichiers et MR sur plateforme/medisphere (jeton de projet, write_repository + api)."""
    base = env("REVUE_GITLAB_URL", "https://git01.par1.medisphere.internal") + "/api/v4"
    projet = quote(env("REVUE_DEPOT_DOC", "plateforme/medisphere"), safe="")
    entetes = {"PRIVATE-TOKEN": env("REVUE_GITLAB_TOKEN_DOC")}
    branche = f"revue-acces/{mois}"
    actions = [{"action": "create", "file_path": f"docs/securite/identite/revue-acces/{f.name}", "content": f.read_text()}
               for f in (md, js)]
    commit = {"branch": branche, "start_branch": "main", "commit_message": f"docs(identite): revue des accès {mois}",
              "actions": actions}
    r = requests.post(f"{base}/projects/{projet}/repository/commits", json=commit, headers=entetes, timeout=DELAI, verify=RACINE)
    r.raise_for_status()
    mr = {"source_branch": branche, "target_branch": "main", "title": f"Revue des accès {mois}",
          "description": "Revue mensuelle produite par le pipeline. **Signature : approbation de Sophie Laurent.**",
          "remove_source_branch": True}
    r = requests.post(f"{base}/projects/{projet}/merge_requests", json=mr, headers=entetes, timeout=DELAI, verify=RACINE)
    r.raise_for_status()
    return r.json()["web_url"]


def principal() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sortie", default="rapport", help="dossier de sortie (Markdown + JSON)")
    parser.add_argument("--precedent", type=Path, help="JSON de la revue précédente (comparaison)")
    parser.add_argument("--envoyer", action="store_true", help="envoyer le rapport à securite@")
    parser.add_argument("--mr", action="store_true", help="ouvrir la MR sur plateforme/medisphere (CI)")
    args = parser.parse_args()

    modele = yaml.safe_load((ICI / "modele.yml").read_text())
    acceptes = yaml.safe_load((ICI / "ecarts-acceptes.yml").read_text()).get("acceptes") or []
    sources = {
        "annuaire": lire_annuaire(), "keycloak": lire_keycloak(), "gitlab": lire_gitlab(),
        "grafana": lire_grafana(), "argocd": lire_argocd(), "kubernetes": lire_kubernetes(), "proxmox": lire_proxmox(),
    }
    revue = analyser(modele, sources)
    appliquer_acceptes(revue, acceptes, dt.date.today())
    precedent = json.loads(args.precedent.read_text()) if args.precedent and args.precedent.exists() else None
    diff = comparer(revue, precedent)

    sortie = Path(args.sortie)
    sortie.mkdir(parents=True, exist_ok=True)
    mois = revue.date[:7]
    md, js = sortie / f"{mois}.md", sortie / f"{mois}.json"
    md.write_text(rendre_markdown(revue, diff))
    js.write_text(json.dumps(rendre_json(revue), ensure_ascii=False, indent=2, sort_keys=True))
    ouverts = sum(1 for e in revue.ecarts if not e.accepte)
    print(f"revue-acces : {len(revue.personnes)} personnes, {ouverts} écart(s) ouvert(s), "
          f"{len(diff['nouveaux'])} nouveau(x) ; {md}")
    if args.envoyer:
        envoyer(f"Revue des accès {mois} : {ouverts} écart(s)", md.read_text(), md)
    if args.mr:
        print(f"revue-acces : MR {publier_mr(md, js, mois)}")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
