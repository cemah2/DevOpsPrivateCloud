"""Tests de outils/netbox-provision.py (M11-E06, version M11-E13) : contrôle et rendu, sans réseau."""

import copy
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

RACINE = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("netbox_provision", RACINE / "outils" / "netbox-provision.py")
np = importlib.util.module_from_spec(_spec)
sys.modules["netbox_provision"] = np  # requis par @dataclass
_spec.loader.exec_module(np)

PARAMETRES = {
    "serveur_http": "https://pxe01.par1.medisphere.internal",
    "domaine": "par1.medisphere.internal",
    "ntp": "10.10.60.1",
    "disque": "sda",
    "rocky_version": "10.2",
    "rocky_miroir": "https://dl.rockylinux.org/pub/rocky",
    "empreinte_racine": "0" * 64,
    "racine_pem": "-----BEGIN CERTIFICATE-----\nRACINE\n-----END CERTIFICATE-----\n",
    "cle_ssh_admin": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEssai admin@adm01",
    "regle_installation": "planned",
    "pve_version": "9.2",
    "pve_noyau_arguments": "ramdisk_size=16777216 rw quiet",
    "reseau": "10.10.60.0/24",
    "plage_debut": "10.10.60.100",
    "plage_fin": "10.10.60.199",
}


@pytest.fixture
def brutes():
    return json.loads((RACINE / "tests" / "donnees" / "netbox.json").read_text(encoding="utf-8"))


def test_quatre_machines_valides_et_triees(brutes):
    bilan = np.controler(list(reversed(brutes)), PARAMETRES)
    assert [m.nom for m in bilan.valides] == ["bm01", "bm02", "bm03", "bm04"]
    assert bilan.refus == []
    assert bilan.valides[1].mac == "02:4d:53:60:00:02"  # normalisée en minuscules


@pytest.mark.parametrize(
    ("champ", "valeur", "motif"),
    [
        ("mac", "", "MAC absente"),
        ("ip", "10.10.99.150/24", "hors de 10.10.60.0/24"),
        ("ip", "10.10.60.20/24", "hors de la plage"),
        ("ip", "", "IP primaire absente"),
        ("plateforme", "windows-2025", "inconnue"),
        ("nom", "serveur-de-test", "hors convention"),
        ("dns_name", "", "dns_name"),
    ],
)
def test_donnee_incoherente_refusee(brutes, champ, valeur, motif):
    b = copy.deepcopy(brutes)
    b[0][champ] = valeur
    bilan = np.controler(b, PARAMETRES)
    assert len(bilan.valides) == 3
    assert len(bilan.refus) == 1 and motif in bilan.refus[0][2]
    assert bilan.refus_bloquants  # bm01 est « planned » : la chaîne doit le signaler


def test_mac_en_double_refuse_les_deux(brutes):
    b = copy.deepcopy(brutes)
    b[2]["mac"] = b[0]["mac"]
    bilan = np.controler(b, PARAMETRES)
    assert {r[0] for r in bilan.refus} == {"bm01", "bm03"}


def test_refus_non_bloquant_si_pas_planned(brutes):
    b = copy.deepcopy(brutes)
    b[3]["mac"] = "pas-une-mac"
    bilan = np.controler(b, PARAMETRES)
    assert bilan.refus and not bilan.refus_bloquants


def test_rendu(brutes, tmp_path):
    bilan = np.controler(brutes, PARAMETRES)
    np.rendre(bilan, PARAMETRES, RACINE / "gabarits", tmp_path / "rendu")
    ipxe = tmp_path / "rendu" / "http" / "ipxe"
    bm01 = (ipxe / "mac-02-4d-53-60-00-01.ipxe").read_text(encoding="utf-8")
    assert bm01.startswith("#!ipxe\n")
    assert "hostname=bm01 domain=par1.medisphere.internal" in bm01
    assert "initrd ${base}/preseed/bm01.cfg /preseed.cfg" in bm01  # remis par iPXE (M11-E13)
    assert "http://" not in bm01
    bm02 = (ipxe / "mac-02-4d-53-60-00-02.ipxe").read_text(encoding="utf-8")
    assert "inst.ks=file:/ks.cfg" in bm02 and "initrd ${base}/kickstart/bm02.ks /ks.cfg" in bm02
    assert "/10.2/BaseOS/" in bm02
    bm03 = (ipxe / "mac-02-4d-53-60-00-03.ipxe").read_text(encoding="utf-8")
    assert "kernel" not in bm03 and "\nexit\n" in bm03  # « active » : disque local
    # Un fichier de réponse par machine à installer, et seulement pour elles.
    assert sorted(p.name for p in (tmp_path / "rendu" / "http" / "kickstart").iterdir()) == ["bm02.ks"]
    assert sorted(p.name for p in (tmp_path / "rendu" / "http" / "preseed").iterdir()) == ["bm01.cfg"]
    ks = (tmp_path / "rendu" / "http" / "kickstart" / "bm02.ks").read_text(encoding="utf-8")
    assert "--hostname=bm02.par1.medisphere.internal" in ks
    assert "rootpw --lock" in ks and "--password" not in ks
    preseed = (tmp_path / "rendu" / "http" / "preseed" / "bm01.cfg").read_text(encoding="utf-8")
    assert "d-i netcfg/get_hostname string bm01" in preseed
    assert "passwd/root-password" not in preseed and "passwd/user-password " not in preseed
    kea = yaml.safe_load((tmp_path / "rendu" / "kea_reservations_prov.yml").read_text(encoding="utf-8"))
    assert kea["kea_reservations_prov"][0] == {"mac": "02:4d:53:60:00:01", "ip": "10.10.60.101", "nom": "bm01"}
    assert len(kea["kea_reservations_prov"]) == 4


def test_rendu_deterministe_et_sans_reste(brutes, tmp_path):
    sortie = tmp_path / "rendu"
    np.rendre(np.controler(brutes, PARAMETRES), PARAMETRES, RACINE / "gabarits", sortie)
    premier = {p.relative_to(sortie): p.read_bytes() for p in sortie.rglob("*") if p.is_file()}
    # bm04 disparaît de NetBox : son script ne doit pas survivre au rendu suivant.
    np.rendre(np.controler(brutes[:3], PARAMETRES), PARAMETRES, RACINE / "gabarits", sortie)
    second = {p.relative_to(sortie): p.read_bytes() for p in sortie.rglob("*") if p.is_file()}
    assert Path("http/ipxe/mac-02-4d-53-60-00-04.ipxe") in premier
    assert Path("http/ipxe/mac-02-4d-53-60-00-04.ipxe") not in second
    np.rendre(np.controler(brutes[:3], PARAMETRES), PARAMETRES, RACINE / "gabarits", sortie)
    troisieme = {p.relative_to(sortie): p.read_bytes() for p in sortie.rglob("*") if p.is_file()}
    assert second == troisieme


@pytest.mark.skipif(shutil.which("ksvalidator") is None, reason="pykickstart absent")
def test_kickstart_rendu_valide(brutes, tmp_path):
    np.rendre(np.controler(brutes, PARAMETRES), PARAMETRES, RACINE / "gabarits", tmp_path / "rendu")
    ks = tmp_path / "rendu" / "http" / "kickstart" / "bm02.ks"
    ksvalidator = shutil.which("ksvalidator")
    assert subprocess.run([ksvalidator, "-v", "RHEL10", str(ks)], check=False).returncode == 0  # noqa: S603


def test_lire_env_sans_executer(tmp_path):
    f = tmp_path / "netbox-ansible.env"
    f.write_text('# commentaire\nexport NETBOX_TOKEN="nbt_abc.def"\nAUTRE=$(touch /tmp/piege)\n', encoding="utf-8")
    assert np.lire_env(f, "NETBOX_TOKEN") == "nbt_abc.def"
    with pytest.raises(np.ErreurAcces):
        np.lire_env(f, "ABSENT")


def test_client_refuse_pagination_vers_autre_hote(monkeypatch):
    nb = np.NetBox("https://nbx01.par1.medisphere.internal", "nbt_x.y", "/dev/null")
    pages = [{"results": [{"id": 1}], "next": "https://ailleurs.example/api/dcim/devices/?offset=200"}]
    monkeypatch.setattr(nb, "_get", lambda url, params=None: pages.pop(0))
    with pytest.raises(np.ErreurAcces):
        nb.liste("dcim/devices/", {})


def test_principal_code_retour(tmp_path, brutes):
    donnees = tmp_path / "netbox.json"
    b = copy.deepcopy(brutes)
    b[1]["plateforme"] = ""
    donnees.write_text(json.dumps(b), encoding="utf-8")
    parametres = tmp_path / "parametres.yml"
    parametres.write_text(yaml.safe_dump(PARAMETRES), encoding="utf-8")
    code = np.principal(
        ["rendre", "--depuis-json", str(donnees), "--parametres", str(parametres), "--sortie", str(tmp_path / "rendu")]
    )
    assert code == 1


def test_regle_pxe_action(brutes, tmp_path):
    """M11-E15 : seul un équipement « staged » avec pxe_action=installer reçoit une installation."""
    b = copy.deepcopy(brutes)
    b[0]["statut"], b[0]["pxe_action"] = "staged", "installer"  # bm01 : à installer
    b[1]["statut"], b[1]["pxe_action"] = "staged", "local"  # bm02 : installé, premier démarrage
    # bm03 et bm04 « active », et un « planned » sans pxe_action ne s'installe plus.
    b[2]["statut"] = "planned"
    parametres = {**PARAMETRES, "regle_installation": "pxe_action"}
    bilan = np.controler(b, parametres)
    np.rendre(bilan, parametres, RACINE / "gabarits", tmp_path / "rendu")
    ipxe = tmp_path / "rendu" / "http" / "ipxe"
    assert "kernel" in (ipxe / "mac-02-4d-53-60-00-01.ipxe").read_text(encoding="utf-8")
    for mac in ("02", "03", "04"):
        assert "kernel" not in (ipxe / f"mac-02-4d-53-60-00-{mac}.ipxe").read_text(encoding="utf-8")
    assert [p.name for p in (tmp_path / "rendu" / "http" / "kickstart").iterdir()] == []


def test_regle_inconnue_refusee(brutes, tmp_path):
    parametres = {**PARAMETRES, "regle_installation": "toujours"}
    with pytest.raises(ValueError):
        np.rendre(np.controler(brutes, parametres), parametres, RACINE / "gabarits", tmp_path / "rendu")
