"""Garde-fous (M02-E16) : fonctions pures, testées sur toutes leurs frontières."""

import pytest

from medictl import garde_fous
from medictl.erreurs import RefusGardeFou


@pytest.mark.parametrize("vmid", [2000, 2020, 2999, 5000, 5555, 5999])
def test_vmid_autorises(vmid):
    garde_fous.verifier_vmid_modifiable(vmid)


@pytest.mark.parametrize(
    ("vmid", "motif"),
    [
        (100, "hors des plages"),
        (999, "hors des plages"),
        (1000, "socle"),
        (1001, "socle"),
        (1099, "socle"),
        (1999, "hors des plages"),
        (3000, "hors des plages"),
        (4999, "hors des plages"),
        (6000, "hors des plages"),
        (9000, "templates"),
        (9099, "templates"),
    ],
)
def test_vmid_refuses(vmid, motif):
    with pytest.raises(RefusGardeFou, match=motif) as exc:
        garde_fous.verifier_vmid_modifiable(vmid)
    assert exc.value.code == 3


def test_vm_hors_pool_refusee(ressources):
    horspool = next(r for r in ressources if r["vmid"] == 2029)
    with pytest.raises(RefusGardeFou, match="hors du pool"):
        garde_fous.verifier_vm_modifiable(horspool)


def test_vm_du_pool_acceptee(ressources):
    garde_fous.verifier_vm_modifiable(next(r for r in ressources if r["vmid"] == 2020))


def test_template_refuse_meme_dans_une_plage_autorisee():
    with pytest.raises(RefusGardeFou, match="template"):
        garde_fous.verifier_vm_modifiable(
            {"vmid": 2025, "type": "qemu", "template": 1, "pool": "lab"}
        )


def test_source_de_clonage(ressources):
    garde_fous.verifier_source_clonage(next(r for r in ressources if r["vmid"] == 9000))
    with pytest.raises(RefusGardeFou, match="plage des templates"):
        garde_fous.verifier_source_clonage(next(r for r in ressources if r["vmid"] == 1002))
    with pytest.raises(RefusGardeFou, match="n'est pas un template"):
        garde_fous.verifier_source_clonage({"vmid": 9001, "template": 0, "pool": "lab"})


@pytest.mark.parametrize("nom", ["m02-test", "a", "sbx01", "x" * 63])
def test_noms_valides(nom):
    garde_fous.verifier_nom(nom)


@pytest.mark.parametrize("nom", ["", "-test", "test-", "M02", "m02_test", "a.b", "x" * 64, "é"])
def test_noms_invalides(nom):
    with pytest.raises(RefusGardeFou):
        garde_fous.verifier_nom(nom)
