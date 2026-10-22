"""Secrets de medictl dans OpenBao (M25-E07). Aucun appel réseau : « responses » sert l'API."""

import pytest
import responses

from medictl.coffre import AccesCoffre, Coffre, ErreurCoffre, charger_acces
from medictl.config import charger_config
from medictl.erreurs import ConfigError

ADRESSE = "https://openbao.test:8200"
ROLE_ID = "11111111-role-role-role-111111111111"
SECRET_ID = "22222222-secr-secr-secr-222222222222"
JETON = "b.AAAAjetonbatchdetest"
SECRET_PVE = "33333333-pve0-pve0-pve0-333333333333"


@pytest.fixture
def acces_coffre(tmp_path, monkeypatch):
    fichier = tmp_path / "medictl-openbao.env"
    fichier.write_text(
        f"BAO_ADDR={ADRESSE}\nMEDICTL_BAO_ROLE_ID={ROLE_ID}\nMEDICTL_BAO_SECRET_ID='{SECRET_ID}'\n"
    )
    fichier.chmod(0o600)
    monkeypatch.setenv("MEDICTL_BAO_ENV_FILE", str(fichier))
    return fichier


def _servir_coffre(statut_lecture=200, champ="token_secret"):
    responses.add(
        responses.POST,
        f"{ADRESSE}/v1/auth/approle/login",
        json={"auth": {"client_token": JETON, "lease_duration": 300}},
        match=[
            responses.matchers.json_params_matcher({"role_id": ROLE_ID, "secret_id": SECRET_ID})
        ],
    )
    responses.add(
        responses.GET,
        f"{ADRESSE}/v1/kv/data/plateforme/medictl/pve",
        json={"data": {"data": {champ: SECRET_PVE}, "metadata": {"version": 3}}}
        if statut_lecture == 200
        else {"errors": ["1 error occurred:\n\t* permission denied\n\n"]},
        status=statut_lecture,
        match=[responses.matchers.header_matcher({"X-Vault-Token": JETON})],
    )


def test_sans_acces_pas_de_coffre():
    assert charger_acces() is None


def test_acces_lu_dans_le_fichier_sans_secret_dans_repr(acces_coffre):
    acces = charger_acces()
    assert acces == AccesCoffre(adresse=ADRESSE, role_id=ROLE_ID, secret_id=SECRET_ID)
    assert SECRET_ID not in repr(acces)
    assert SECRET_ID not in repr(Coffre(acces))


def test_fichier_d_acces_trop_ouvert_refuse(acces_coffre):
    acces_coffre.chmod(0o640)
    with pytest.raises(ConfigError, match="mode 640"):
        charger_acces()


def test_acces_incomplets(tmp_path, monkeypatch):
    monkeypatch.setenv("MEDICTL_BAO_ROLE_ID", ROLE_ID)
    with pytest.raises(ConfigError, match="MEDICTL_BAO_SECRET_ID"):
        charger_acces()


def test_http_refuse(acces_coffre, monkeypatch):
    monkeypatch.setenv("BAO_ADDR", "http://openbao.test:8200")
    with pytest.raises(ConfigError, match="https"):
        charger_acces()


@responses.activate
def test_lecture_du_secret(acces_coffre):
    _servir_coffre()
    assert Coffre(charger_acces()).lire("plateforme/medictl/pve", "token_secret") == SECRET_PVE


@responses.activate
def test_refus_du_coffre_sans_fuite(acces_coffre):
    _servir_coffre(statut_lecture=403)
    with pytest.raises(ErreurCoffre, match="403") as erreur:
        Coffre(charger_acces()).lire("plateforme/medictl/pve", "token_secret")
    assert SECRET_ID not in str(erreur.value) and JETON not in str(erreur.value)


@responses.activate
def test_champ_absent(acces_coffre):
    _servir_coffre(champ="autre")
    with pytest.raises(ErreurCoffre, match="token_secret"):
        Coffre(charger_acces()).lire("plateforme/medictl/pve", "token_secret")


@responses.activate
def test_configuration_pve_complete_par_le_coffre(acces_coffre, tmp_path, monkeypatch):
    # pve-api.env SANS secret (état normal depuis M25-E07)
    pve = tmp_path / "pve-api.env"
    pve.write_text(
        "PVE_API_URL=https://pve.test:8006/api2/json\nPVE_NODE=pve01\nPVE_TOKEN_ID='wb-automation@pve!lab'\n"
    )
    pve.chmod(0o600)
    monkeypatch.setenv("MEDICTL_ENV_FILE", str(pve))
    for cle in ("PVE_API_URL", "PVE_NODE", "PVE_TOKEN_ID", "PVE_TOKEN_SECRET", "PVE_CACERT"):
        monkeypatch.delenv(cle, raising=False)
    _servir_coffre()
    cfg = charger_config()
    assert cfg.token_secret == SECRET_PVE
    assert cfg.sources["PVE_TOKEN_SECRET"] == "openbao (kv/plateforme/medictl/pve)"
    assert SECRET_PVE not in repr(cfg)
    assert cfg.affichable()["PVE_TOKEN_SECRET"].startswith("****")


@responses.activate
def test_secret_local_prioritaire_pas_d_appel_au_coffre(acces_coffre, fichier_env):
    # Un PVE_TOKEN_SECRET encore présent dans le fichier : le coffre n'est pas appelé.
    cfg = charger_config()
    assert cfg.sources["PVE_TOKEN_SECRET"] == str(fichier_env)
    assert len(responses.calls) == 0


@responses.activate
def test_chemin_du_secret_choisi_par_le_fichier_pve(acces_coffre, tmp_path, monkeypatch):
    # pve-lecture.env (synchronisation NetBox, M06) : autre jeton, autre chemin dans le coffre.
    pve = tmp_path / "pve-lecture.env"
    pve.write_text(
        "PVE_API_URL=https://pve.test:8006/api2/json\nPVE_NODE=pve01\n"
        "PVE_TOKEN_ID='wb-lecture@pve!netbox'\nMEDICTL_BAO_CHEMIN_PVE=plateforme/medictl/pve-lecture\n"
    )
    pve.chmod(0o600)
    monkeypatch.setenv("MEDICTL_ENV_FILE", str(pve))
    for cle in ("PVE_API_URL", "PVE_NODE", "PVE_TOKEN_ID", "PVE_TOKEN_SECRET", "PVE_CACERT"):
        monkeypatch.delenv(cle, raising=False)
    responses.add(
        responses.POST,
        f"{ADRESSE}/v1/auth/approle/login",
        json={"auth": {"client_token": JETON}},
    )
    responses.add(
        responses.GET,
        f"{ADRESSE}/v1/kv/data/plateforme/medictl/pve-lecture",
        json={"data": {"data": {"token_secret": "lecture-seule"}}},
    )
    cfg = charger_config()
    assert cfg.token_secret == "lecture-seule"
    assert cfg.sources["PVE_TOKEN_SECRET"] == "openbao (kv/plateforme/medictl/pve-lecture)"
