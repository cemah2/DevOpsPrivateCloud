from __future__ import annotations

import os
from pathlib import Path

import pytest

from mediagenda.migrate import ErreurMigration, a_appliquer, decouvrir, migrer

MIGRATIONS = Path(__file__).resolve().parent.parent / "migrations"


def test_migrations_du_depot_dans_l_ordre():
    migrations = decouvrir(MIGRATIONS)
    assert [m.chemin.name for m in migrations][:2] == ["V1__init.sql", "V2__index.sql"]


def test_tri_numerique_et_non_alphabetique(tmp_path):
    for nom in ("V10__dix.sql", "V2__deux.sql", "V2_1__deux_un.sql", "V1__un.sql"):
        (tmp_path / nom).write_text("SELECT 1;")
    assert [m.version_texte for m in decouvrir(tmp_path)] == ["1", "2", "2.1", "10"]


def test_nom_non_conforme(tmp_path):
    (tmp_path / "init.sql").write_text("SELECT 1;")
    with pytest.raises(ErreurMigration, match="non conforme"):
        decouvrir(tmp_path)


def test_version_en_double(tmp_path):
    (tmp_path / "V1__a.sql").write_text("SELECT 1;")
    (tmp_path / "V01__b.sql").write_text("SELECT 2;")
    with pytest.raises(ErreurMigration, match="double"):
        decouvrir(tmp_path)


def test_seules_les_nouvelles_sont_appliquees(tmp_path):
    (tmp_path / "V1__a.sql").write_text("SELECT 1;")
    (tmp_path / "V2__b.sql").write_text("SELECT 2;")
    migrations = decouvrir(tmp_path)
    deja = {"1": migrations[0].empreinte}
    assert [m.version_texte for m in a_appliquer(migrations, deja)] == ["2"]


def test_migration_modifiee_refusee(tmp_path):
    (tmp_path / "V1__a.sql").write_text("SELECT 1;")
    with pytest.raises(ErreurMigration, match="modifiée"):
        a_appliquer(decouvrir(tmp_path), {"1": "autre-empreinte"})


@pytest.mark.integration
def test_migrer_sur_vrai_postgresql():
    url = os.environ.get("MEDIAGENDA_TEST_DB_URL")
    if not url:
        pytest.skip("MEDIAGENDA_TEST_DB_URL non définie")
    migrer(url, MIGRATIONS)
    assert migrer(url, MIGRATIONS) == []  # idempotent
