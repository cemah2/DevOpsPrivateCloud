"""tests/test_rendre.py — tests du générateur (plateforme/equipes, F2-S02). Aucun accès réseau."""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "outils"))

import rendre


@pytest.fixture()
def donnees():
    config, brutes = rendre.charger(rendre.RACINE)
    return config, brutes


def _equipes(brutes):
    return [rendre.normaliser(d) for d in brutes]


def test_les_equipes_du_depot_sont_valides(donnees):
    config, brutes = donnees
    rendre.controler(config, _equipes(brutes))


def test_quantites():
    assert rendre.quantite("500m") == rendre.Decimal("0.5")
    assert rendre.quantite("3Gi") == 3 * 1024**3
    assert rendre.quantite(2) == 2
    with pytest.raises(rendre.Invalide):
        rendre.quantite("3 Go")


def test_budget_depasse_refuse(donnees):
    config, brutes = donnees
    b = copy.deepcopy(brutes)
    medivisio = next(d for d in b if d["metadata"]["nom"] == "medivisio")
    medivisio["spec"]["kubernetes"]["budget"]["requests.memory"] = "1Gi"
    with pytest.raises(rendre.Invalide, match="dépassent le budget"):
        rendre.controler(config, _equipes(b))


def test_nom_reserve_refuse(donnees):
    config, brutes = donnees
    b = copy.deepcopy(brutes)
    b[0]["metadata"]["nom"] = "mediagenda"
    with pytest.raises(rendre.Invalide, match="réservé"):
        rendre.controler(config, _equipes(b))


def test_responsable_absent_refuse(donnees):
    config, brutes = donnees
    b = copy.deepcopy(brutes)
    b[0]["spec"]["responsable"] = "personne.inconnue"
    with pytest.raises(rendre.Invalide, match="responsable"):
        rendre.controler(config, _equipes(b))


def test_rendu_complet_et_lisible(donnees, tmp_path):
    config, brutes = donnees
    equipes = _equipes(brutes)
    rendre.rendre_identite(equipes, tmp_path)
    rendre.rendre_secrets(equipes, tmp_path)
    rendre.rendre_grafana(equipes, tmp_path)
    rendre.rendre_k8s_gitops(config, equipes, tmp_path)
    rendre.verifier_rendu(tmp_path)
    # Chaque environnement a son espace, et chaque espace est rattaché à son locataire.
    for e in equipes:
        for env in e["environnements"]:
            ns = yaml.safe_load_all((tmp_path / f"k8s/equipes/{e['nom']}/espaces/{e['nom']}-{env}.yaml").read_text())
            namespace = next(o for o in ns if o and o["kind"] == "Namespace")
            assert namespace["metadata"]["labels"]["capsule.clastix.io/tenant"] == e["nom"]
    # Le projet Argo CD de l'ApplicationSet est écrit en dur (jamais une valeur du générateur).
    aset = yaml.safe_load((tmp_path / "gitops/equipes/medivisio/services.yaml").read_text())
    assert aset["spec"]["template"]["spec"]["project"] == "medivisio"
    # La liste des utilisateurs Capsule contient les équipes existantes ET les nouvelles.
    users = yaml.safe_load((tmp_path / "gitops/valeurs/capsule/utilisateurs-equipes.yaml").read_text())
    noms = [u["name"] for u in users["manager"]["options"]["users"]]
    assert {"oidc:mediagenda", "oidc:medidoc", "oidc:medivisio", "oidc:data"} <= set(noms)
    secrets = json.loads((tmp_path / "secrets/tofu/equipes.auto.tfvars.json").read_text())
    assert secrets["equipes_en_code"]["medivisio"]["environnements"] == ["dev", "prod", "recette"]


def test_equipe_retiree_desactive_et_ne_rend_plus_de_droits(donnees, tmp_path):
    config, brutes = donnees
    b = copy.deepcopy(brutes)
    data = next(d for d in b if d["metadata"]["nom"] == "data")
    data["spec"]["etat"] = "retiree"
    equipes = _equipes(b)
    rendre.rendre_identite(equipes, tmp_path)
    rendre.rendre_secrets(equipes, tmp_path)
    rendre.rendre_k8s_gitops(config, equipes, tmp_path)
    personnes = yaml.safe_load((tmp_path / "identite/annuaire/equipes/personnes.yml").read_text())["annuaire_personnes_equipes"]
    assert all(p["etat"] == "disabled" for p in personnes if p["identifiant"] in ("hugo.bernard", "sarah.colin"))
    groupes = yaml.safe_load((tmp_path / "identite/annuaire/equipes/groupes.yml").read_text())["annuaire_groupes_equipes"]
    assert next(g for g in groupes if g["nom"] == "data")["membres"] == []
    assert "data" not in json.loads((tmp_path / "secrets/tofu/equipes.auto.tfvars.json").read_text())["equipes_en_code"]
    assert not (tmp_path / "k8s/equipes/data").exists()
