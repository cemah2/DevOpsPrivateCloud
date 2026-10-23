"""Tests de contrat côté PRODUCTEUR : l'API tient-elle le contrat v1 du GHSV ? (F7-S09, DEV-3709)

Le contrat est le fichier reçu du client, versionné sans modification dans contrats/ghsv/ (son
empreinte est vérifiée contre ORIGINE.md : on ne « corrige » pas le contrat pour faire passer un test).
Ces tests tournent SANS cluster ni base (dépôt et cache en mémoire de conftest.py), sur chaque MR :
  1. chaque opération du contrat existe dans l'application (chemin + méthode) ;
  2. pour chaque opération, des requêtes conformes au contrat reçoivent les codes que le contrat
     promet, et les corps de réponse sont VALIDÉS contre les schémas du contrat (JSON Schema 2020-12,
     les schémas d'OpenAPI 3.1 en sont un dialecte) ;
  3. l'authentification décrite par le contrat (jeton porteur, portées rdv:lecture et rdv:ecriture)
     est appliquée quand l'instance l'exige (MEDIAGENDA_PORTEES=oui).
Ce qu'ils NE vérifient PAS : le réseau, TLS, la publication (Gateway, OAuth2 Proxy), les vraies
requêtes SQL (le dépôt PostgreSQL est couvert par les tests d'intégration) — d'où la recette du client.
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
from pathlib import Path

import pytest
import yaml
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

from mediagenda.app import create_app
from mediagenda.config import Settings

pytestmark = pytest.mark.contrat

DOSSIER = Path(__file__).resolve().parent.parent / "contrats" / "ghsv"
CONTRAT_FICHIER = DOSSIER / "api-rendez-vous-v1.yaml"
CONTRAT = yaml.safe_load(CONTRAT_FICHIER.read_text(encoding="utf-8"))
URN = "urn:medisphere:contrat:ghsv:v1"
REGISTRE = Registry().with_resource(
    URN, Resource.from_contents(CONTRAT, default_specification=DRAFT202012)
)
# Préfixe des chemins : celui de « servers » du contrat (https://{hote}/api/v1).
PREFIXE = re.sub(r"^https://\{hote\}", "", CONTRAT["servers"][0]["url"])
METHODES = ("get", "post", "put", "patch", "delete")

RDV = {
    "patient": "Patient Fictif",
    "praticien": "P004217",  # identifiant du DPI du GHSV : « P » + six chiffres (réponse R-07)
    "debut": "2027-03-08T09:00:00+01:00",
    "duree_minutes": 30,
    "motif": "Consultation de suivi",
    "rappel": {"canal": "sms", "contact": "+33 6 00 00 00 00"},
}


def jeton(*portees: str, groupes: tuple[str, ...] = ()) -> dict[str, str]:
    """En-tête Authorization avec un JWT NON signé : en production, la signature est vérifiée par le
    mandataire (oauth2-proxy-dpi) avant l'API ; ici on teste ce que fait l'API d'un jeton vérifié."""

    def b64(d: dict) -> str:
        return base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()

    charge = {
        "iss": "https://sso.par1.medisphere.internal/realms/medisphere",
        "scope": " ".join(portees),
    }
    if groupes:
        charge["groups"] = list(groupes)
    return {"Authorization": f"Bearer {b64({'alg': 'none', 'typ': 'JWT'})}.{b64(charge)}.signature"}


LECTURE = jeton("rdv:lecture")
TOUT = jeton("rdv:lecture", "rdv:ecriture")


def valider(corps, nom_schema: str) -> None:
    """Valide un corps de réponse contre un schéma nommé du contrat (components/schemas)."""
    Draft202012Validator(
        {"$ref": f"{URN}#/components/schemas/{nom_schema}"}, registry=REGISTRE
    ).validate(corps)


def schema_reponse(chemin: str, methode: str, code: int) -> dict | None:
    """Schéma JSON de la réponse décrite par le contrat (références de réponses résolues)."""
    rep = CONTRAT["paths"][chemin][methode]["responses"][str(code)]
    if "$ref" in rep:
        rep = CONTRAT["components"]["responses"][rep["$ref"].rsplit("/", 1)[1]]
    contenu = rep.get("content", {}).get("application/json")
    return contenu["schema"] if contenu else None


def verifier(reponse, chemin: str, methode: str, attendu: int) -> None:
    """Le code est celui attendu, il est PROMIS par le contrat, et le corps respecte son schéma."""
    assert reponse.status_code == attendu, reponse.text
    assert str(attendu) in CONTRAT["paths"][chemin][methode]["responses"], (
        f"{attendu} absent du contrat"
    )
    schema = schema_reponse(chemin, methode, attendu)
    if schema is not None:
        Draft202012Validator(_resoudre(schema), registry=REGISTRE).validate(reponse.json())


def _resoudre(schema: dict) -> dict:
    """Réécrit les références internes « #/components/… » du contrat vers son URN."""
    texte = json.dumps(schema).replace('"#/components/', f'"{URN}#/components/')
    return json.loads(texte)


@pytest.fixture
def client_ghsv(depot, cache):
    reglages = Settings(
        db_url="postgresql://test",
        valkey_url="redis://test",
        version="1.2.3",
        titre=CONTRAT["info"]["title"],
        portees=True,
    )
    with TestClient(create_app(reglages, depot=depot, cache=cache)) as c:
        yield c


# --- 0. Le contrat lui-même ----------------------------------------------------------------------


def test_contrat_intact():
    """Le fichier est celui reçu du GHSV : même empreinte que celle consignée dans ORIGINE.md."""
    consignee = re.search(
        r"sha256 : `([0-9a-f]{64})`", (DOSSIER / "ORIGINE.md").read_text(encoding="utf-8")
    )
    assert consignee, "empreinte absente de contrats/ghsv/ORIGINE.md"
    assert hashlib.sha256(CONTRAT_FICHIER.read_bytes()).hexdigest() == consignee.group(1)


# --- 1. Toutes les opérations existent -----------------------------------------------------------


@pytest.mark.parametrize(
    ("chemin", "methode"),
    [(c, m) for c, ops in CONTRAT["paths"].items() for m in ops if m in METHODES],
)
def test_operation_presente(client_ghsv, chemin, methode):
    servi = client_ghsv.app.openapi()["paths"]
    # Le contrat nomme le paramètre {id}, l'application {rdv_id} : seul le gabarit compte.
    gabarits = {re.sub(r"\{[^}]+\}", "{}", c): ops for c, ops in servi.items()}
    cible = re.sub(r"\{[^}]+\}", "{}", PREFIXE + chemin)
    assert cible in gabarits, f"chemin absent : {PREFIXE + chemin}"
    assert methode in gabarits[cible], f"opération absente : {methode.upper()} {PREFIXE + chemin}"


def test_titre_marque_blanche(client_ghsv):
    assert client_ghsv.get("/openapi.json").json()["info"]["title"] == CONTRAT["info"]["title"]


# --- 2. Comportements promis ---------------------------------------------------------------------


def test_creneaux(client_ghsv):
    r = client_ghsv.get(
        f"{PREFIXE}/creneaux",
        params={"date": "2027-03-08", "praticien": "P004217"},
        headers=LECTURE,
    )
    verifier(r, "/creneaux", "get", 200)
    assert r.json()["fuseau"] == "Europe/Paris"
    verifier(client_ghsv.get(f"{PREFIXE}/creneaux", headers=LECTURE), "/creneaux", "get", 422)


def test_creation_conflit_et_date_sans_decalage(client_ghsv):
    verifier(
        client_ghsv.post(f"{PREFIXE}/rendez-vous", json=RDV, headers=TOUT),
        "/rendez-vous",
        "post",
        201,
    )
    verifier(
        client_ghsv.post(f"{PREFIXE}/rendez-vous", json=RDV, headers=TOUT),
        "/rendez-vous",
        "post",
        409,
    )
    sans_decalage = {**RDV, "debut": "2027-03-08T10:00:00"}
    verifier(
        client_ghsv.post(f"{PREFIXE}/rendez-vous", json=sans_decalage, headers=TOUT),
        "/rendez-vous",
        "post",
        422,
    )


def test_creation_minimale_rend_rappel_et_duree(client_ghsv):
    """Le contrat exige rappel et duree_minutes dans la réponse, même s'ils ne sont pas envoyés."""
    minimal = {
        "patient": "Patient Fictif",
        "praticien": "P000001",
        "debut": "2027-03-08T11:00:00+01:00",
    }
    r = client_ghsv.post(f"{PREFIXE}/rendez-vous", json=minimal, headers=TOUT)
    verifier(r, "/rendez-vous", "post", 201)
    assert r.json()["rappel"]["canal"] == "aucun" and r.json()["duree_minutes"] == 30


def test_liste_filtree_du_dpi(client_ghsv):
    for heure, praticien in (
        ("09:00", "P004217"),
        ("09:30", "P004217"),
        ("09:00", "P009999"),
        ("14:00", "P004217"),
    ):
        rdv = {**RDV, "praticien": praticien, "debut": f"2027-03-08T{heure}:00+01:00"}
        assert client_ghsv.post(f"{PREFIXE}/rendez-vous", json=rdv, headers=TOUT).status_code == 201
    params = {
        "praticien": "P004217",
        "du": "2027-03-08T08:00:00+01:00",
        "au": "2027-03-08T12:00:00+01:00",
    }
    r = client_ghsv.get(f"{PREFIXE}/rendez-vous", params=params, headers=LECTURE)
    verifier(r, "/rendez-vous", "get", 200)
    debuts = [x["debut"] for x in r.json()]
    assert len(debuts) == 2 and debuts == sorted(debuts)
    assert all(x["praticien"] == "P004217" for x in r.json())


def test_detail_introuvable_et_identifiant_invalide(client_ghsv):
    cree = client_ghsv.post(f"{PREFIXE}/rendez-vous", json=RDV, headers=TOUT).json()
    verifier(
        client_ghsv.get(f"{PREFIXE}/rendez-vous/{cree['id']}", headers=LECTURE),
        "/rendez-vous/{id}",
        "get",
        200,
    )
    verifier(
        client_ghsv.get(f"{PREFIXE}/rendez-vous/999999", headers=LECTURE),
        "/rendez-vous/{id}",
        "get",
        404,
    )
    verifier(
        client_ghsv.get(f"{PREFIXE}/rendez-vous/0", headers=LECTURE),
        "/rendez-vous/{id}",
        "get",
        422,
    )


def test_deplacement_atomique(client_ghsv):
    a = client_ghsv.post(f"{PREFIXE}/rendez-vous", json=RDV, headers=TOUT).json()
    b = client_ghsv.post(
        f"{PREFIXE}/rendez-vous", json={**RDV, "debut": "2027-03-09T14:30:00+01:00"}, headers=TOUT
    ).json()
    # Créneau pris : 409, et le rendez-vous reste à son heure d'origine.
    r = client_ghsv.patch(
        f"{PREFIXE}/rendez-vous/{a['id']}", json={"debut": b["debut"]}, headers=TOUT
    )
    verifier(r, "/rendez-vous/{id}", "patch", 409)
    assert (
        client_ghsv.get(f"{PREFIXE}/rendez-vous/{a['id']}", headers=LECTURE).json()["debut"]
        == a["debut"]
    )
    # Créneau libre : 200, même identifiant, même patient, même rappel.
    r = client_ghsv.patch(
        f"{PREFIXE}/rendez-vous/{a['id']}",
        json={"debut": "2027-03-10T08:30:00+01:00"},
        headers=TOUT,
    )
    verifier(r, "/rendez-vous/{id}", "patch", 200)
    assert (
        r.json()["id"] == a["id"]
        and r.json()["patient"] == a["patient"]
        and r.json()["rappel"] == a["rappel"]
    )
    verifier(
        client_ghsv.patch(
            f"{PREFIXE}/rendez-vous/999999", json={"debut": RDV["debut"]}, headers=TOUT
        ),
        "/rendez-vous/{id}",
        "patch",
        404,
    )


def test_annulation(client_ghsv):
    cree = client_ghsv.post(f"{PREFIXE}/rendez-vous", json=RDV, headers=TOUT).json()
    verifier(
        client_ghsv.delete(f"{PREFIXE}/rendez-vous/{cree['id']}", headers=TOUT),
        "/rendez-vous/{id}",
        "delete",
        204,
    )
    verifier(
        client_ghsv.delete(f"{PREFIXE}/rendez-vous/{cree['id']}", headers=TOUT),
        "/rendez-vous/{id}",
        "delete",
        404,
    )


# --- 3. Authentification et portées --------------------------------------------------------------


def test_sans_jeton_401(client_ghsv):
    verifier(client_ghsv.get(f"{PREFIXE}/rendez-vous"), "/rendez-vous", "get", 401)
    verifier(client_ghsv.post(f"{PREFIXE}/rendez-vous", json=RDV), "/rendez-vous", "post", 401)


def test_portee_insuffisante_403(client_ghsv):
    """Le contrat ne liste pas 403 : écart E-08 de ecarts-contrat-v1.md (question au GHSV). On répond
    403 « insufficient_scope » (RFC 6750 §3.1) ; ce test documente le choix et le garde stable."""
    r = client_ghsv.post(f"{PREFIXE}/rendez-vous", json=RDV, headers=LECTURE)
    assert r.status_code == 403
    valider(r.json(), "Erreur")


def test_agent_du_client_a_les_deux_portees(client_ghsv):
    agent = jeton(groupes=("ghsv-agents",))
    assert client_ghsv.post(f"{PREFIXE}/rendez-vous", json=RDV, headers=agent).status_code == 201
    assert client_ghsv.get(f"{PREFIXE}/rendez-vous", headers=agent).status_code == 200


def test_sondes_et_description_sans_jeton(client_ghsv):
    assert client_ghsv.get("/pret").status_code == 200
    assert client_ghsv.get("/openapi.json").status_code == 200


def test_cabinets_inchanges(client):
    """Une instance des cabinets (sans MEDIAGENDA_PORTEES) n'exige aucun jeton et garde son titre."""
    assert client.post("/api/v1/rendez-vous", json=RDV).status_code == 201
    assert client.get("/openapi.json").json()["info"]["title"] == "MédiAgenda"
