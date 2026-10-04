"""ClientPVE au niveau HTTP (M02-E17, E18) : « responses » intercepte requests,
donc proxmoxer. On vérifie les requêtes réellement émises (méthode, URL,
paramètres, en-tête d'authentification), les reprises et la traduction des erreurs.
"""

import json
import re

import pytest
import requests
import responses

from medictl.config import PveConfig
from medictl.erreurs import ErreurApi
from medictl.pve import ClientPVE

from .conftest import DONNEES, SECRET, UPID

BASE = "https://pve.test:8006/api2/json"


@pytest.fixture
def pauses() -> list[float]:
    return []


@pytest.fixture
def client(pauses) -> ClientPVE:
    cfg = PveConfig(
        api_url=BASE,
        node="pve01",
        token_id="wb-automation@pve!lab",
        token_secret=SECRET,
        cacert=None,
    )
    reel = ClientPVE.depuis_config(cfg)
    # Même API, mais des pauses enregistrées au lieu d'être subies.
    return ClientPVE(reel._api, dormir=pauses.append)


@pytest.fixture
def api():
    with responses.RequestsMock(assert_all_requests_are_fired=False) as mock:
        yield mock


def _ressources():
    return {"data": json.loads((DONNEES / "cluster-resources.json").read_text())}


def test_vms_filtre_trie_et_authentifie(client, api):
    api.get(f"{BASE}/cluster/resources", json=_ressources())
    vms = client.vms()
    assert [v["vmid"] for v in vms][:3] == [1000, 1001, 1002]
    requete = api.calls[0].request
    assert requete.url == f"{BASE}/cluster/resources?type=vm"
    assert requete.headers["Authorization"] == f"PVEAPIToken=wb-automation@pve!lab={SECRET}"


def test_lecture_reprise_sur_503_avec_delais_croissants(client, api, pauses):
    url = f"{BASE}/cluster/resources"
    api.get(url, status=503)
    api.get(url, status=503)
    api.get(url, json=_ressources())
    assert len(client.vms()) == 9
    assert len(api.calls) == 3
    assert pauses == [1.0, 2.0]


def test_lecture_reprise_sur_coupure_reseau_puis_abandon(client, api, pauses):
    api.get(f"{BASE}/cluster/resources", body=requests.exceptions.ConnectionError("refusé"))
    with pytest.raises(ErreurApi, match="injoignable"):
        client.vms()
    assert len(api.calls) == 4
    assert pauses == [1.0, 2.0, 4.0]


@pytest.mark.parametrize(
    ("statut", "motif"), [(401, "jeton refusé"), (403, "droits insuffisants"), (400, "HTTP 400")]
)
def test_erreurs_4xx_jamais_reprises(client, api, pauses, statut, motif):
    api.get(f"{BASE}/cluster/resources", status=statut, json={"data": None})
    with pytest.raises(ErreurApi, match=motif):
        client.vms()
    assert len(api.calls) == 1
    assert pauses == []


def test_erreur_tls_jamais_reprise(client, api, pauses):
    api.get(
        f"{BASE}/cluster/resources", body=requests.exceptions.SSLError("certificate verify failed")
    )
    with pytest.raises(ErreurApi, match="PVE_CACERT"):
        client.vms()
    assert len(api.calls) == 1


def test_ecriture_jamais_reprise(client, api, pauses):
    api.post(f"{BASE}/nodes/pve01/qemu/9000/clone", status=503)
    with pytest.raises(ErreurApi, match="HTTP 503"):
        client.cloner({"vmid": 9000, "node": "pve01"}, 2022, "m02-test", "lab")
    assert len(api.calls) == 1
    corps = api.calls[0].request.body
    assert "newid=2022" in corps and "pool=lab" in corps and "name=m02-test" in corps


def test_vmid_libre(client, api):
    api.get(f"{BASE}/cluster/nextid", json={"data": 2022})
    assert client.vmid_libre(2022) is True
    api.replace(
        responses.GET,
        f"{BASE}/cluster/nextid",
        status=400,
        json={"data": None, "errors": {"vmid": "VM 2020 already exists"}},
    )
    assert client.vmid_libre(2020) is False


def test_attendre_tache_jusqu_a_ok(client, api, pauses):
    upid = UPID.format(type="qmclone", vmid=9000)
    url = re.compile(re.escape(f"{BASE}/nodes/pve01/tasks/") + r".+/status")
    api.get(url, json={"data": {"status": "running"}})
    api.get(url, json={"data": {"status": "stopped", "exitstatus": "OK"}})
    client.attendre_tache(upid, intervalle=2)
    assert len(api.calls) == 2
    assert pauses == [2]
    assert "qmclone" in api.calls[0].request.url


def test_attendre_tache_en_echec(client, api):
    api.get(
        re.compile(re.escape(f"{BASE}/nodes/pve01/tasks/") + r".+/status"),
        json={"data": {"status": "stopped", "exitstatus": "clone failed: no space left"}},
    )
    with pytest.raises(ErreurApi, match="no space left"):
        client.attendre_tache(UPID.format(type="qmclone", vmid=9000))


def test_detruire_purge_tout(client, api):
    api.delete(
        f"{BASE}/nodes/pve01/qemu/2022", json={"data": UPID.format(type="qmdestroy", vmid=2022)}
    )
    assert client.detruire("pve01", 2022).startswith("UPID:")
    assert "purge=1" in api.calls[0].request.url
    assert "destroy-unreferenced-disks=1" in api.calls[0].request.url


def test_adresses_ipv4_via_agent(client, api):
    api.get(
        f"{BASE}/nodes/pve01/qemu/1002/agent/network-get-interfaces",
        json={"data": json.loads((DONNEES / "network-get-interfaces.json").read_text())},
    )
    assert client.adresses_ipv4({"node": "pve01", "vmid": 1002}) == ["10.10.20.10"]


def test_adresses_ipv4_agent_muet(client, api):
    api.get(f"{BASE}/nodes/pve01/qemu/2021/agent/network-get-interfaces", status=500)
    assert client.adresses_ipv4({"node": "pve01", "vmid": 2021}) == []
