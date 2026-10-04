"""Configuration et secrets (M02-E19)."""

import logging

import pytest
import responses

from medictl import config, journal
from medictl.cli import app
from medictl.config import charger_config, lire_fichier_env
from medictl.erreurs import ConfigError

from .conftest import SECRET


def test_lecture_du_fichier_sans_l_executer(fichier_env, tmp_path):
    cfg = charger_config()
    assert cfg.api_url == "https://pve.test:8006/api2/json"
    assert cfg.node == "pve01"  # commentaire en fin de ligne ignoré
    assert cfg.token_id == "wb-automation@pve!lab"  # apostrophes : « ! » littéral
    assert cfg.utilisateur == "wb-automation@pve"
    assert cfg.nom_jeton == "lab"
    assert cfg.cacert == str(tmp_path / "ca.pem")  # $HOME développé
    assert cfg.hote == "pve.test" and cfg.port == 8006


def test_le_fichier_n_est_jamais_execute(tmp_path):
    temoin = tmp_path / "pirate"
    fichier = tmp_path / "env"
    fichier.write_text(f'PVE_NODE="$(touch {temoin})"\n')
    assert lire_fichier_env(fichier)["PVE_NODE"] == f"$(touch {temoin})"
    assert not temoin.exists()


def test_environnement_prioritaire_sur_le_fichier(fichier_env, monkeypatch):
    monkeypatch.setenv("PVE_NODE", "pve02")
    cfg = charger_config()
    assert cfg.node == "pve02"
    assert cfg.sources["PVE_NODE"] == "environnement"
    assert cfg.sources["PVE_API_URL"] == str(fichier_env)


def test_fichier_trop_ouvert_refuse(fichier_env):
    fichier_env.chmod(0o644)
    with pytest.raises(ConfigError, match="mode 644"):
        charger_config()


def test_config_incomplete(tmp_path, monkeypatch):
    for cle in ("PVE_API_URL", "PVE_NODE", "PVE_TOKEN_ID", "PVE_TOKEN_SECRET", "PVE_CACERT"):
        monkeypatch.delenv(cle, raising=False)
    monkeypatch.setenv("MEDICTL_ENV_FILE", str(tmp_path / "absent.env"))
    with pytest.raises(ConfigError, match="manque : PVE_API_URL, PVE_NODE"):
        charger_config()


def test_config_uniquement_par_l_environnement(tmp_path, monkeypatch):
    monkeypatch.setenv("MEDICTL_ENV_FILE", str(tmp_path / "absent.env"))
    monkeypatch.setenv("PVE_API_URL", "https://10.0.0.1:8006/api2/json")
    monkeypatch.setenv("PVE_NODE", "pve01")
    monkeypatch.setenv("PVE_TOKEN_ID", "ci@pve!test")
    monkeypatch.setenv("PVE_TOKEN_SECRET", SECRET)
    monkeypatch.delenv("PVE_CACERT", raising=False)
    cfg = charger_config()
    # Magasin du système s'il existe (Debian), sinon True (certifi) : jamais False.
    assert cfg.verification_tls in (config.MAGASIN_SYSTEME, True)


@pytest.mark.parametrize(
    ("cle", "valeur", "motif"),
    [
        ("PVE_API_URL", "http://pve.test:8006/api2/json", "https://"),
        ("PVE_API_URL", "https://pve.test:8006/", "/api2/json"),
        ("PVE_TOKEN_ID", "wb-automation@pve", "utilisateur@domaine!jeton"),
        ("PVE_CACERT", "/nulle/part.pem", "illisible"),
    ],
)
def test_valeurs_invalides(fichier_env, monkeypatch, cle, valeur, motif):
    monkeypatch.setenv(cle, valeur)
    with pytest.raises(ConfigError, match=motif):
        charger_config()


def test_le_secret_n_apparait_pas_dans_repr(fichier_env):
    assert SECRET not in repr(charger_config())


def test_commande_config_masque_le_secret(runner, fichier_env):
    resultat = runner.invoke(app, ["config"])
    assert resultat.exit_code == 0
    assert SECRET not in resultat.output
    assert "PVE_TOKEN_SECRET=****" in resultat.stdout


def test_commande_config_erreur_claire(runner, fichier_env):
    fichier_env.chmod(0o640)
    resultat = runner.invoke(app, ["config"])
    assert resultat.exit_code == 1
    assert "corrige ses droits" in resultat.stderr


def test_filtre_de_journal_masque_le_secret(capsys):
    journal.configurer_journal(2)
    journal.masquer(SECRET)
    logging.getLogger("medictl.test").warning("en-tête : PVEAPIToken=x=%s", SECRET)
    sortie = capsys.readouterr().err
    assert SECRET not in sortie
    assert "PVEAPIToken=x=****" in sortie


def test_aucun_secret_a_l_ecran_meme_en_mode_bavard(runner, fichier_env):
    with responses.RequestsMock() as api:
        api.get(
            "https://pve.test:8006/api2/json/cluster/resources",
            json={"data": [{"type": "qemu", "vmid": 2020, "name": "m02-cobaye", "pool": "lab"}]},
        )
        resultat = runner.invoke(app, ["-vvv", "vm", "list", "-f", "json"])
    assert resultat.exit_code == 0, resultat.output
    assert SECRET not in resultat.output
    assert '"vmid": 2020' in resultat.stdout
