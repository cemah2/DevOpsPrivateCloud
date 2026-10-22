"""Tests de bin/ms-ci-conformite sur des réponses enregistrées de l'API ci/lint (sans réseau)."""
import importlib.machinery
import importlib.util
import json
import pathlib
import tomllib

RACINE = pathlib.Path(__file__).resolve().parents[1]
_chargeur = importlib.machinery.SourceFileLoader("conformite", str(RACINE / "bin" / "ms-ci-conformite"))
_spec = importlib.util.spec_from_loader("conformite", _chargeur)
conformite = importlib.util.module_from_spec(_spec)
_chargeur.exec_module(conformite)

REGLES = tomllib.loads((RACINE / "etc" / "ci-conformite.toml").read_text(encoding="utf-8"))
DONNEES = RACINE / "tests" / "donnees"


def lint(nom):
    return json.loads((DONNEES / f"{nom}.json").read_text(encoding="utf-8"))


def test_projet_conforme():
    assert conformite.evaluer({"only_allow_merge_if_pipeline_succeeds": True}, lint("lint-conforme"), REGLES) == []


def test_version_trop_ancienne_et_fusion_libre():
    e = conformite.evaluer({"only_allow_merge_if_pipeline_succeeds": False}, lint("lint-v200"), REGLES)
    assert any(x.startswith("R3") for x in e)
    assert any(x.startswith("R4") for x in e)


def test_composant_absent():
    e = conformite.evaluer({"only_allow_merge_if_pipeline_succeeds": True}, lint("lint-sans-composant"), REGLES)
    assert e == ["R2 : composant plateforme/ci-templates/securite non inclus"]


def test_securite_facultative():
    e = conformite.evaluer({"only_allow_merge_if_pipeline_succeeds": True}, lint("lint-facultatif"), REGLES)
    assert e == ["R5 : le job securite:trivy est rendu facultatif (allow_failure: true)"]


def test_sans_configuration():
    assert conformite.evaluer({}, None, REGLES)[0].startswith("R1")


def test_version_prefixee_v_acceptee():
    assert conformite.version("v2.8.0") == (2, 8, 0)


def test_projet_sans_image():
    pr = {"path_with_namespace": "mediagenda/deploiement", "only_allow_merge_if_pipeline_succeeds": True}
    assert conformite.evaluer(pr, lint("lint-sans-composant"), REGLES) == []
