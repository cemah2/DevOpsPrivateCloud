"""Tests contre un vrai PostgreSQL et un vrai Valkey (sautés par défaut).

    MEDIAGENDA_TEST_DB_URL=postgresql://mediagenda:<MOT-DE-PASSE>@127.0.0.1:5432/mediagenda_test \\
    MEDIAGENDA_TEST_VALKEY_URL=redis://127.0.0.1:6379/15 \\
    uv run pytest -m integration

⚠️ La base de test est vidée (DROP SCHEMA public CASCADE) : jamais une vraie base.
"""

from __future__ import annotations

import os
from pathlib import Path

import psycopg
import pytest
from fastapi.testclient import TestClient

from mediagenda.app import create_app
from mediagenda.config import Settings
from mediagenda.migrate import migrer

pytestmark = pytest.mark.integration
MIGRATIONS = Path(__file__).resolve().parent.parent / "migrations"


@pytest.fixture
def client_reel():
    db = os.environ.get("MEDIAGENDA_TEST_DB_URL")
    valkey = os.environ.get("MEDIAGENDA_TEST_VALKEY_URL")
    if not (db and valkey):
        pytest.skip("MEDIAGENDA_TEST_DB_URL et MEDIAGENDA_TEST_VALKEY_URL non définies")
    with psycopg.connect(db, autocommit=True) as conn:
        conn.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public")
    migrer(db, MIGRATIONS)
    with TestClient(create_app(Settings(db_url=db, valkey_url=valkey))) as c:
        yield c


def test_bout_en_bout(client_reel):
    assert client_reel.get("/pret").status_code == 200
    rdv = {"patient": "Test", "praticien": "dr-test", "debut": "2026-11-02T10:00:00+01:00"}
    cree = client_reel.post("/api/v1/rendez-vous", json=rdv)
    assert cree.status_code == 201
    assert client_reel.post("/api/v1/rendez-vous", json=rdv).status_code == 409
    libres = client_reel.get(
        "/api/v1/creneaux", params={"date": "2026-11-02", "praticien": "dr-test"}
    ).json()["libres"]
    assert "2026-11-02T10:00:00+01:00" not in libres
    rdv_id = cree.json()["id"]
    assert client_reel.get(f"/api/v1/rendez-vous/{rdv_id}").json()["praticien"] == "dr-test"
    assert client_reel.delete(f"/api/v1/rendez-vous/{rdv_id}").status_code == 204
