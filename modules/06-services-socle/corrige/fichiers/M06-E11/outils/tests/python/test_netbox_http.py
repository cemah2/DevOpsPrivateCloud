"""Tests du client HTTP NetBox (M06-E11) : configuration, en-tête, pagination, erreurs."""

from __future__ import annotations

import pytest
import requests
import responses

from medictl.erreurs import ConfigError, ErreurApi
from medictl.netbox import ClientNetbox, NetboxConfig, charger_config_netbox

URL = "https://nbx01.par1.medisphere.internal"
JETON = "nbt_AbCdEf123456.faux-secret-de-test-0000000000"


def client() -> ClientNetbox:
    return ClientNetbox.depuis_config(NetboxConfig(url=URL, jeton=JETON))


def test_config_lit_le_fichier_en_600(tmp_path):
    f = tmp_path / "netbox-auto.token"
    f.write_text(JETON + "\n")
    f.chmod(0o600)
    cfg = charger_config_netbox({"MEDICTL_NETBOX_TOKEN_FILE": str(f)})
    assert cfg.jeton == JETON
    assert cfg.url == URL
    assert JETON not in repr(cfg)


def test_config_refuse_un_fichier_lisible_par_d_autres(tmp_path):
    f = tmp_path / "netbox-auto.token"
    f.write_text(JETON)
    f.chmod(0o644)
    with pytest.raises(ConfigError, match="accessible"):
        charger_config_netbox({"MEDICTL_NETBOX_TOKEN_FILE": str(f)})


def test_config_refuse_un_jeton_v1():
    with pytest.raises(ConfigError, match="v2"):
        charger_config_netbox({"NETBOX_TOKEN": "0123456789abcdef0123456789abcdef01234567"})


def test_config_refuse_http_et_chemin_api():
    with pytest.raises(ConfigError, match="https"):
        charger_config_netbox({"NETBOX_TOKEN": JETON, "NETBOX_URL": "http://nbx01"})
    with pytest.raises(ConfigError, match="sans /api"):
        charger_config_netbox({"NETBOX_TOKEN": JETON, "NETBOX_URL": URL + "/api"})


@responses.activate
def test_en_tete_bearer_et_pagination():
    responses.get(
        f"{URL}/api/dcim/sites/",
        json={
            "count": 3,
            "next": f"{URL}/api/dcim/sites/?limit=2&offset=2",
            "results": [{"id": 1}, {"id": 2}],
        },
        match=[responses.matchers.query_param_matcher({"limit": "200", "status": "active"})],
    )
    responses.get(
        f"{URL}/api/dcim/sites/?limit=2&offset=2",
        json={"count": 3, "next": None, "results": [{"id": 3}]},
    )
    assert [s["id"] for s in client().lister("dcim/sites/", status="active")] == [1, 2, 3]
    assert responses.calls[0].request.headers["Authorization"] == f"Bearer {JETON}"


@responses.activate
def test_pagination_vers_un_autre_hote_refusee():
    responses.get(
        f"{URL}/api/dcim/sites/",
        json={
            "count": 2,
            "next": "https://ailleurs.example/api/dcim/sites/?offset=1",
            "results": [{"id": 1}],
        },
    )
    with pytest.raises(ErreurApi, match="next"):
        client().lister("dcim/sites/")


@responses.activate
def test_403_explique():
    responses.post(
        f"{URL}/api/extras/tags/",
        status=403,
        json={"detail": "You do not have permission to perform this action."},
    )
    with pytest.raises(ErreurApi, match="403"):
        client().creer("extras/tags/", {"name": "x", "slug": "x"})


@responses.activate
def test_unique_refuse_plusieurs_resultats():
    responses.get(
        f"{URL}/api/virtualization/clusters/",
        json={"count": 2, "next": None, "results": [{"id": 1}, {"id": 2}]},
    )
    with pytest.raises(ErreurApi, match="2 objets"):
        client().unique("virtualization/clusters/", name="pve01")


@responses.activate
def test_lecture_reprise_apres_coupure_ecriture_jamais(monkeypatch):
    monkeypatch.setattr("medictl.reprises.time.sleep", lambda _s: None)
    responses.get(f"{URL}/api/status/", body=requests.exceptions.ConnectionError("coupure"))
    responses.get(f"{URL}/api/status/", json={"netbox-version": "4.6.10"})
    assert client()._lire("status/")["netbox-version"] == "4.6.10"

    responses.patch(
        f"{URL}/api/virtualization/virtual-machines/5/",
        body=requests.exceptions.ConnectionError("coupure"),
    )
    with pytest.raises(ErreurApi, match="injoignable"):
        client().modifier("virtualization/virtual-machines/", 5, {"vcpus": 2})
    assert sum(1 for c in responses.calls if c.request.method == "PATCH") == 1
