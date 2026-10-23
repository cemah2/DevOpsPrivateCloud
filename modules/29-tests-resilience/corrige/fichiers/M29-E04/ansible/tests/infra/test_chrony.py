"""Client de temps (partie « temps » du rôle base, M04-E10/E15, NTS en M06-E21, sources en M07-E25).

Le rôle pose /etc/chrony/chrony.conf (sources = les deux passerelles du VLAN, .2 et .3, en NTS),
désactive ms-ntp-passerelle de l'image dorée, et attend la synchronisation. On vérifie le
RÉSULTAT : chrony tourne, ses sources sont les bonnes, il est synchronisé, NTS est négocié.
Les passerelles (gw01, gw02) sont SERVEURS de temps (chrony_serveur) : hors périmètre ici.
"""

import re

import pytest

pytestmark = pytest.mark.chrony


@pytest.fixture(autouse=True)
def _clients_seulement(est_passerelle):
    if est_passerelle:
        pytest.skip("passerelle : serveur de temps (rôle chrony_serveur), pas client")


@pytest.fixture(scope="module")
def sources_attendues(adresse_defaut):
    """Les deux passerelles du VLAN de l'hôte : 10.10.<VLAN>.2 et .3 (M07-E25)."""
    prefixe = adresse_defaut.rsplit(".", 1)[0]
    return [f"{prefixe}.2", f"{prefixe}.3"]


def test_service_chrony_actif_et_au_demarrage(host, famille):
    service = host.service("chronyd" if famille == "rocky" else "chrony")
    assert service.is_running
    assert service.is_enabled


def test_configuration_sources_des_passerelles_en_nts(host, sources_attendues):
    conf = host.file("/etc/chrony/chrony.conf")
    assert conf.exists, "configuration du rôle base absente"
    for source in sources_attendues:
        assert re.search(rf"^server {re.escape(source)} iburst nts$", conf.content_string, re.M), (
            f"source {source} absente ou sans NTS"
        )


def test_aucune_autre_source(host):
    contenu = host.file("/etc/chrony/chrony.conf").content_string
    # Ni pool Internet, ni dossier de sources déposées hors d'Ansible (DHCP, M00-E31).
    assert not re.search(r"^\s*(pool|sourcedir)\b", contenu, re.M)


def test_mecanisme_de_l_image_desactive(host):
    unite = host.service("ms-ntp-passerelle")
    if unite.exists:
        assert not unite.is_enabled, "ms-ntp-passerelle (image dorée) choisirait encore la source"


def test_horloge_synchronisee(host):
    suivi = host.check_output("chronyc -n tracking")
    assert re.search(r"^Leap status\s*:\s*Normal$", suivi, re.M), suivi
    # Une source sélectionnée (« ^* ») parmi les passerelles.
    sources = host.check_output("chronyc -n sources")
    assert re.search(r"^\^\*\s+10\.10\.\d+\.[23]\b", sources, re.M), sources


def test_ecart_inferieur_a_100_ms(host):
    suivi = host.check_output("chronyc -n tracking")
    ecart = re.search(r"^System time\s*:\s*([0-9.]+) seconds", suivi, re.M)
    assert ecart and float(ecart.group(1)) < 0.1, suivi


def test_nts_negocie(host):
    # « authdata » passe par la socket de commande : réservé à root.
    with host.sudo():
        auth = host.check_output("chronyc -n authdata")
    lignes = [ligne for ligne in auth.splitlines() if re.match(r"^10\.10\.", ligne)]
    assert lignes, auth
    assert all(ligne.split()[1] == "NTS" for ligne in lignes), auth
