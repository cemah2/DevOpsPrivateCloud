from __future__ import annotations

import json
import logging

from mediagenda.app import create_app

RDV = {
    "patient": "Jeanne Dupont",
    "praticien": "dr-morel",
    "debut": "2026-11-02T09:00:00+01:00",
    "motif": "Contrôle annuel",
}


def test_sante_ne_touche_pas_aux_dependances(client, depot, cache):
    depot.en_panne = cache.en_panne = True
    r = client.get("/sante")
    assert r.status_code == 200
    assert r.json() == {"statut": "ok", "version": "1.2.3"}


def test_pret_ok(client):
    r = client.get("/pret")
    assert r.status_code == 200
    assert r.json() == {"statut": "pret", "postgresql": "ok", "valkey": "ok"}


def test_pret_503_si_postgresql_absent(client, depot):
    depot.en_panne = True
    r = client.get("/pret")
    assert r.status_code == 503
    assert r.json()["postgresql"] == "indisponible"
    assert r.json()["valkey"] == "ok"


def test_pret_503_si_valkey_absent(client, cache):
    cache.en_panne = True
    r = client.get("/pret")
    assert r.status_code == 503
    assert r.json()["valkey"] == "indisponible"


def test_cycle_complet_rendez_vous(client):
    r = client.post("/api/v1/rendez-vous", json=RDV)
    assert r.status_code == 201
    cree = r.json()
    assert cree["id"] == 1
    assert cree["duree_minutes"] == 30

    assert client.get("/api/v1/rendez-vous").json()[0]["id"] == 1
    assert client.get("/api/v1/rendez-vous/1").json()["patient"] == "Jeanne Dupont"

    assert client.delete("/api/v1/rendez-vous/1").status_code == 204
    assert client.get("/api/v1/rendez-vous/1").status_code == 404
    assert client.delete("/api/v1/rendez-vous/1").status_code == 404


def test_double_reservation_409(client):
    assert client.post("/api/v1/rendez-vous", json=RDV).status_code == 201
    assert client.post("/api/v1/rendez-vous", json=RDV).status_code == 409


def test_date_sans_fuseau_refusee(client):
    r = client.post("/api/v1/rendez-vous", json={**RDV, "debut": "2026-11-02T09:00:00"})
    assert r.status_code == 422


def test_creneaux_mis_en_cache(client, depot, cache):
    r1 = client.get("/api/v1/creneaux", params={"date": "2026-11-02", "praticien": "dr-morel"})
    assert r1.status_code == 200
    libres = r1.json()["libres"]
    assert len(libres) == 16  # 8h-12h et 14h-18h, pas de 30 min
    assert libres[0] == "2026-11-02T08:00:00+01:00"
    assert cache.ttl["mediagenda:creneaux:dr-morel:2026-11-02"] == 60

    r2 = client.get("/api/v1/creneaux", params={"date": "2026-11-02", "praticien": "dr-morel"})
    assert r2.json() == r1.json()
    assert depot.appels_creneaux == 1  # le second appel vient du cache


def test_creation_invalide_le_cache(client, depot):
    params = {"date": "2026-11-02", "praticien": "dr-morel"}
    client.get("/api/v1/creneaux", params=params)
    client.post("/api/v1/rendez-vous", json=RDV)
    libres = client.get("/api/v1/creneaux", params=params).json()["libres"]
    assert depot.appels_creneaux == 2
    assert "2026-11-02T09:00:00+01:00" not in libres
    assert len(libres) == 15


def test_creneaux_tous_praticiens_par_defaut(client):
    client.post("/api/v1/rendez-vous", json=RDV)
    corps = client.get("/api/v1/creneaux", params={"date": "2026-11-02"}).json()
    assert corps["praticien"] == "tous"
    assert len(corps["libres"]) == 15


def test_creneaux_sans_cache_mode_degrade(client, cache):
    cache.en_panne = True
    r = client.get("/api/v1/creneaux", params={"date": "2026-11-02"})
    assert r.status_code == 200
    assert len(r.json()["libres"]) == 16


def test_creneaux_date_obligatoire(client):
    assert client.get("/api/v1/creneaux").status_code == 422


def test_metrics(client):
    client.get("/api/v1/rendez-vous/42")
    texte = client.get("/metrics").text
    assert "mediagenda_http_requests_total" in texte
    assert "mediagenda_http_request_duration_seconds_bucket" in texte
    # le modèle de route, pas l'identifiant réel
    assert 'route="/api/v1/rendez-vous/{rdv_id}"' in texte


def test_une_ligne_json_par_requete(client, caplog):
    from mediagenda.journal import FormateurJson

    with caplog.at_level(logging.INFO, logger="mediagenda.acces"):
        client.post("/api/v1/rendez-vous", json=RDV)
    lignes = [r for r in caplog.records if r.name == "mediagenda.acces"]
    assert len(lignes) == 1
    ligne = json.loads(FormateurJson().format(lignes[0]))
    assert ligne["methode"] == "POST"
    assert ligne["route"] == "/api/v1/rendez-vous"
    assert ligne["code"] == 201
    assert "Jeanne" not in json.dumps(ligne)  # pas de donnée patient dans le journal


def test_arret_ferme_les_connexions(settings, depot, cache):
    from fastapi.testclient import TestClient

    with TestClient(create_app(settings, depot=depot, cache=cache)):
        pass
    assert depot.ferme and cache.ferme
