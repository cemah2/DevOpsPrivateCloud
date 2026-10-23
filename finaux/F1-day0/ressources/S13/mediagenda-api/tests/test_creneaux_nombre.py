"""DEV-3113 : nombre de créneaux libres dans la réponse de /api/v1/creneaux."""

from __future__ import annotations

from mediagenda.modeles import Creneaux

RDV = {
    "patient": "Jeanne Dupont",
    "praticien": "dr-morel",
    "debut": "2026-11-02T09:00:00+01:00",
    "motif": "Contrôle annuel",
}
PARAMS = {"date": "2026-11-02", "praticien": "dr-morel"}


def test_nombre_egal_a_la_liste(client):
    corps = client.get("/api/v1/creneaux", params=PARAMS).json()
    assert corps["nombre"] == len(corps["libres"]) == 16


def test_nombre_suit_les_reservations(client):
    client.get("/api/v1/creneaux", params=PARAMS)
    client.post("/api/v1/rendez-vous", json=RDV)
    corps = client.get("/api/v1/creneaux", params=PARAMS).json()
    assert corps["nombre"] == 15


def test_reponse_en_cache_d_une_version_precedente(client, cache):
    # Valeur écrite en cache par la version N-1 (sans « nombre ») : toujours servie, champ ajouté.
    ancienne = (
        '{"date":"2026-11-02","praticien":"dr-morel","fuseau":"Europe/Paris",'
        '"libres":["2026-11-02T08:00:00+01:00","2026-11-02T08:30:00+01:00"]}'
    )
    cache.donnees["mediagenda:creneaux:dr-morel:2026-11-02"] = ancienne
    corps = client.get("/api/v1/creneaux", params=PARAMS).json()
    assert corps["nombre"] == 2


def test_nombre_n_est_pas_une_entree():
    # Un client (ou un cache) qui enverrait « nombre » ne peut pas l'imposer.
    c = Creneaux.model_validate(
        {
            "date": "2026-11-02",
            "praticien": "x",
            "fuseau": "Europe/Paris",
            "libres": [],
            "nombre": 99,
        }
    )
    assert c.nombre == 0
