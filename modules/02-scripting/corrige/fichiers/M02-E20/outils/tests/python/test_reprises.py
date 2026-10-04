"""Politique de reprise (M02-E17) : qu'est-ce qui est transitoire ?"""

import pytest
import requests
from proxmoxer import ResourceException

from medictl.reprises import avec_reprises, est_transitoire


def _http(code: int) -> ResourceException:
    return ResourceException(code, "motif", "contenu")


@pytest.mark.parametrize(
    ("exc", "attendu"),
    [
        (requests.exceptions.ConnectionError(), True),
        (requests.exceptions.ConnectTimeout(), True),
        (requests.exceptions.ReadTimeout(), True),
        (requests.exceptions.SSLError(), False),  # sous-classe de ConnectionError !
        (_http(500), True),
        (_http(503), True),
        (_http(596), True),  # erreur interne de pveproxy (AnyEvent)
        (_http(501), False),
        (_http(400), False),
        (_http(401), False),
        (_http(403), False),
        (ValueError("bogue"), False),
    ],
)
def test_est_transitoire(exc, attendu):
    assert est_transitoire(exc) is attendu


def test_succes_sans_pause():
    pauses = []
    assert avec_reprises(lambda: 42, nom="essai", dormir=pauses.append) == 42
    assert pauses == []


def test_erreur_permanente_relancee_immediatement():
    pauses, essais = [], []

    def appel():
        essais.append(1)
        raise _http(403)

    with pytest.raises(ResourceException):
        avec_reprises(appel, nom="essai", dormir=pauses.append)
    assert len(essais) == 1
    assert pauses == []


def test_delais_exponentiels_puis_abandon(caplog):
    pauses = []

    def appel():
        raise requests.exceptions.ConnectionError()

    with pytest.raises(requests.exceptions.ConnectionError):
        avec_reprises(appel, nom="essai", tentatives=5, delai=0.5, dormir=pauses.append)
    assert pauses == [0.5, 1.0, 2.0, 4.0]
    assert "essai 4/5" in caplog.text
