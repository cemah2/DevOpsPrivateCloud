"""Tests du profil k8s-noeud (F1-S06) : contrôle et rendu sur données simulées, sans réseau.

À poser à côté de tests/test_netbox_provision.py (M11-E06/E13) ; même chargement du module.
Données : tests/donnees/netbox-k8s.json (les données du M11, netbox.json, restent inchangées).
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest
import yaml

RACINE = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("netbox_provision", RACINE / "outils" / "netbox-provision.py")
np = importlib.util.module_from_spec(_spec)
sys.modules["netbox_provision"] = np  # requis par @dataclass
_spec.loader.exec_module(np)


@pytest.fixture
def parametres() -> dict:
    return yaml.safe_load((RACINE / "parametres.yml").read_text(encoding="utf-8"))


@pytest.fixture
def brutes() -> list[dict]:
    return json.loads((RACINE / "tests" / "donnees" / "netbox-k8s.json").read_text(encoding="utf-8"))


def test_k8s_w03_adresse_de_provisioning_et_de_service(brutes, parametres):
    bilan = np.controler(brutes, parametres)
    w03 = next(m for m in bilan.valides if m.nom == "k8s-w03")
    assert w03.ip == "10.10.60.163/24"  # réservation Kea, démarrage réseau
    assert w03.service_adresse == "10.10.40.63/24"  # écrite dans le système installé
    assert w03.service_passerelle == "10.10.40.1"


def test_essai_une_seule_adresse(brutes, parametres):
    bilan = np.controler(brutes, parametres)
    essai = next(m for m in bilan.valides if m.nom == "f1-usine-essai")
    assert essai.ip == essai.service_adresse == "10.10.60.191/24"


@pytest.mark.parametrize(
    ("champ", "valeur", "motif"),
    [
        ("ips", ["10.10.40.63/24"], "adresse de provisioning"),
        ("ips", ["10.10.40.63/24", "10.10.60.163/24", "10.10.60.164/24"], "adresse de provisioning"),
        ("nom", "noeud-k8s", "hors convention"),
        ("ip_service", "", "adresse de service"),
    ],
)
def test_k8s_incoherent_refuse(brutes, parametres, champ, valeur, motif):
    b = next(x for x in brutes if x["nom"] == "k8s-w03")
    b[champ] = valeur
    bilan = np.controler(brutes, parametres)
    assert any(motif in r[2] for r in bilan.refus)


def test_rendu_preseed_k8s(brutes, parametres, tmp_path):
    bilan = np.controler(brutes, parametres)
    np.rendre(bilan, parametres, RACINE / "gabarits", tmp_path)
    preseed = (tmp_path / "http" / "preseed" / "k8s-w03.cfg").read_text(encoding="utf-8")
    assert "choose_recipe select k8s-noeud" in preseed
    assert "linux-swap" not in preseed
    assert "10.10.40.63/24" in preseed and "via: 10.10.40.1" in preseed
    ipxe = (tmp_path / "http" / "ipxe" / "mac-bc-24-11-40-00-63.ipxe").read_text(encoding="utf-8")
    assert "/preseed/k8s-w03.cfg /preseed.cfg" in ipxe
