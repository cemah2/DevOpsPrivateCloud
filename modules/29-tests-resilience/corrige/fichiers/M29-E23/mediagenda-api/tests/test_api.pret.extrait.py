# mediagenda/api — tests/test_api.py (EXTRAIT M29-E23, DEV-3013) : remplace test_pret_503_si_valkey_absent.
def test_pret_200_degrade_si_valkey_absent(client, cache):
    # Valkey est un cache : son absence dégrade sans retirer le pod du Service (M29-E13, INC-5623).
    cache.en_panne = True
    r = client.get("/pret")
    assert r.status_code == 200
    assert r.json() == {"statut": "degrade", "postgresql": "ok", "valkey": "indisponible"}


def test_pret_503_si_postgresql_et_valkey_absents(client, depot, cache):
    depot.en_panne = True
    cache.en_panne = True
    r = client.get("/pret")
    assert r.status_code == 503
    assert r.json()["statut"] == "pas-pret"


