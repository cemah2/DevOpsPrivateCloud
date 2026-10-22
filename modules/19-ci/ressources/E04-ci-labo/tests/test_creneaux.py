import pytest

from labo import creneaux_libres, duree_totale


def test_matinee_sans_rendez_vous():
    assert creneaux_libres(480, 600, 30, []) == [(480, 510), (510, 540), (540, 570), (570, 600)]


def test_creneau_occupe_retire():
    assert (510, 540) not in creneaux_libres(480, 600, 30, [(515, 530)])


def test_duree_totale():
    assert duree_totale([(480, 510), (540, 600)]) == 90


@pytest.mark.parametrize(("debut", "fin", "duree"), [(480, 600, 0), (600, 480, 30)])
def test_parametres_invalides(debut, fin, duree):
    with pytest.raises(ValueError):
        creneaux_libres(debut, fin, duree, [])
