"""tests/test_rendre.py — tests AJOUTÉS par F7-S07 (PLAT-3707), à placer à la suite des tests de F2.
Ils réutilisent la fixture « donnees » et l'aide « _equipes » du fichier existant. Aucun accès réseau.

Le plus important est le dernier : le rendu des équipes existantes ne change pas quand un client arrive
(contrainte du ticket). Il compare deux rendus complets, avec et sans equipes/ghsv.yaml.
"""

from __future__ import annotations

import copy
import filecmp
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

import rendre  # importé par le fichier de tests existant (sys.path déjà réglé)

RACINE = Path(__file__).resolve().parent.parent


def _client(brutes):
    return next(d for d in brutes if d["spec"]["type"] == "client")


def test_le_client_du_depot_est_valide(donnees):
    config, brutes = donnees
    rendre.controler(config, _equipes(brutes))  # noqa: F821 (aide du fichier existant)
    assert _client(brutes)["metadata"]["nom"] == "ghsv"


def test_client_sans_bloc_client_refuse(donnees):
    config, brutes = donnees
    b = copy.deepcopy(brutes)
    del _client(b)["spec"]["client"]
    with pytest.raises(rendre.Invalide, match="bloc « client »"):
        rendre.controler(config, _equipes(b))  # noqa: F821


def test_bloc_client_interdit_a_une_equipe_interne(donnees):
    config, brutes = donnees
    b = copy.deepcopy(brutes)
    interne = next(d for d in b if d["spec"]["type"] == "interne")
    interne["spec"]["client"] = copy.deepcopy(_client(b)["spec"]["client"])
    with pytest.raises(rendre.Invalide, match="réservé au type client"):
        rendre.controler(config, _equipes(b))  # noqa: F821


def test_groupe_des_agents_distinct_du_groupe_du_compte(donnees):
    config, brutes = donnees
    b = copy.deepcopy(brutes)
    _client(b)["spec"]["client"]["identite"]["groupe_agents"] = "ghsv"
    with pytest.raises(rendre.Invalide, match="groupe des agents"):
        rendre.controler(config, _equipes(b))  # noqa: F821


def test_production_du_client_manuelle(donnees):
    config, brutes = donnees
    b = copy.deepcopy(brutes)
    _client(b)["spec"]["kubernetes"]["environnements"]["prod"]["synchronisation"] = "automatique"
    with pytest.raises(rendre.Invalide, match="se synchronise à la main"):
        rendre.controler(config, _equipes(b))  # noqa: F821


def test_rendu_du_client(tmp_path):
    sortie = tmp_path / "rendu"
    r = subprocess.run(
        [sys.executable, str(RACINE / "outils/rendre.py"), "--sortie", str(sortie)], capture_output=True, text=True
    )
    assert r.returncode == 0, r.stderr
    projet = yaml.safe_load((sortie / "gitops/equipes/ghsv/projet.yaml").read_text(encoding="utf-8"))
    assert projet["spec"]["sourceRepos"] == ["https://git01.par1.medisphere.internal/mediagenda/deploiement.git"]
    assert {d["namespace"] for d in projet["spec"]["destinations"]} == {"ghsv-recette", "ghsv-prod"}
    appset = yaml.safe_load((sortie / "gitops/equipes/ghsv/client.yaml").read_text(encoding="utf-8"))
    assert appset["spec"]["template"]["spec"]["source"]["path"].startswith("overlays/clients/ghsv-")
    assert not (sortie / "gitops/equipes/ghsv/services.yaml").exists()
    utilisateurs = (sortie / "gitops/valeurs/capsule/utilisateurs-equipes.yaml").read_text(encoding="utf-8")
    assert "oidc:ghsv" not in utilisateurs
    espace = yaml.safe_load((sortie / "k8s/equipes/ghsv/espaces/ghsv-prod.yaml").read_text(encoding="utf-8").split("\n---\n")[0])
    assert espace["metadata"]["labels"]["medisphere.internal/client"] == "ghsv"
    secrets = yaml.safe_load((sortie / "secrets/tofu/equipes.auto.tfvars.json").read_text(encoding="utf-8"))
    assert secrets["clients_en_code"]["ghsv"]["cles"] == ["exports", "sauvegardes", "signature"]


def test_le_rendu_des_equipes_existantes_ne_change_pas(tmp_path):
    """Contrainte du ticket : même rendu octet pour octet pour les équipes qui ne sont pas des clients
    (à la seule exception, voulue, du tfvars de plateforme/secrets qui porte la clé clients_en_code)."""
    copie = tmp_path / "depot"
    shutil.copytree(RACINE, copie, ignore=shutil.ignore_patterns("rendu", ".venv", ".git", "__pycache__"))
    for avec_client, nom in ((True, "avec"), (False, "sans")):
        if not avec_client:
            (copie / "equipes/ghsv.yaml").unlink()
        r = subprocess.run(
            [sys.executable, str(copie / "outils/rendre.py"), "--racine", str(copie), "--sortie", str(tmp_path / nom)],
            capture_output=True,
            text=True,
        )
        assert r.returncode == 0, r.stderr
    avec, sans = tmp_path / "avec", tmp_path / "sans"
    for f in sorted(p.relative_to(sans) for p in sans.rglob("*") if p.is_file()):
        if str(f) in ("secrets/tofu/equipes.auto.tfvars.json", "gitops/valeurs/capsule/utilisateurs-equipes.yaml"):
            continue
        assert filecmp.cmp(avec / f, sans / f, shallow=False), f"rendu modifié pour une équipe existante : {f}"
