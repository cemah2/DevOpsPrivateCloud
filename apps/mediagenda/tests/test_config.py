from __future__ import annotations

import pytest

from mediagenda.config import ErreurConfiguration, Settings

BASE = {
    "MEDIAGENDA_DB_URL": "postgresql://mediagenda@localhost/mediagenda",
    "MEDIAGENDA_VALKEY_URL": "redis://localhost:6379/0",
}


def test_valeurs_par_defaut():
    s = Settings.depuis_env(BASE)
    assert s.log_level == "INFO"
    assert s.log_format == "json"
    assert s.port == 8000
    assert s.cache_ttl == 60
    assert s.version == "dev"


def test_variables_obligatoires():
    with pytest.raises(ErreurConfiguration, match="MEDIAGENDA_DB_URL"):
        Settings.depuis_env({"MEDIAGENDA_VALKEY_URL": "redis://x"})


@pytest.mark.parametrize(
    ("nom", "valeur"),
    [
        ("MEDIAGENDA_LOG_LEVEL", "BAVARD"),
        ("MEDIAGENDA_LOG_FORMAT", "xml"),
        ("MEDIAGENDA_PORT", "huit"),
    ],
)
def test_valeurs_invalides(nom, valeur):
    with pytest.raises(ErreurConfiguration, match=nom):
        Settings.depuis_env({**BASE, nom: valeur})


def test_surcharges():
    s = Settings.depuis_env(
        {
            **BASE,
            "MEDIAGENDA_LOG_LEVEL": "debug",
            "MEDIAGENDA_VERSION": "1.4.0",
            "MEDIAGENDA_PORT": "9000",
        }
    )
    assert (s.log_level, s.version, s.port) == ("DEBUG", "1.4.0", 9000)
