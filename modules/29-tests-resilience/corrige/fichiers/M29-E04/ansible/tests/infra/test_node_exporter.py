"""Rôle node_exporter, version 2 (M21-E08) : binaire amont épinglé, TLS step-ca, unité durcie.

Deux points de vue : depuis l'hôte (fichiers, service, socket) et depuis le CONTRÔLEUR (adm01 ou
runner01), comme Prometheus le voit : HTTPS vérifié par la racine MédiSphère, HTTP refusé.
"""

import pytest
import testinfra

pytestmark = pytest.mark.node_exporter

VERSION = "1.12.1"
PORT = 9100


def test_binaire_epingle(host):
    lien = host.file("/usr/local/bin/node_exporter")
    assert lien.is_symlink
    assert lien.linked_to == f"/opt/node_exporter/{VERSION}/node_exporter"
    sortie = host.run("/usr/local/bin/node_exporter --version")
    assert f"version {VERSION}" in sortie.stdout + sortie.stderr


def test_paquet_debian_de_la_v1_retire(host, famille):
    if famille != "debian":
        pytest.skip("paquet Debian seulement")
    assert not host.package("prometheus-node-exporter").is_installed


def test_compte_systeme_sans_shell(host):
    compte = host.user("node_exporter")
    assert compte.exists
    assert compte.shell == "/usr/sbin/nologin"


def test_service_actif_et_durci(host):
    service = host.service("node_exporter")
    assert service.is_running
    assert service.is_enabled
    proprietes = service.systemd_properties
    assert proprietes["User"] == "node_exporter"
    assert proprietes["NoNewPrivileges"] == "yes"
    assert proprietes["ProtectSystem"] == "strict"


def test_ecoute_sur_l_adresse_de_service(host, adresse_defaut, est_passerelle):
    # Passerelles : 0.0.0.0, filtré par nftables (M21-E08) ; les autres : l'adresse de la route
    # par défaut seulement.
    adresse = "0.0.0.0" if est_passerelle else adresse_defaut
    assert host.socket(f"tcp://{adresse}:{PORT}").is_listening


def test_configuration_tls(host):
    with host.sudo():
        web = host.file("/etc/node_exporter/web.yml")
        assert web.exists
        assert web.group == "node_exporter"
        assert web.mode == 0o640
        assert "tls_server_config:" in web.content_string


def test_metrique_d_inventaire(host):
    assert host.file("/var/lib/prometheus/node-exporter/medisphere.prom").exists


@pytest.mark.reseau
def test_https_verifie_depuis_le_controleur(nom_hote):
    controleur = testinfra.get_host("local://")
    url = f"https://{nom_hote}.par1.medisphere.internal:{PORT}/metrics"
    resultat = controleur.run("curl -sS --fail --max-time 10 %s", url)
    assert resultat.rc == 0, resultat.stderr
    assert f'version="{VERSION}"' in resultat.stdout


@pytest.mark.reseau
def test_http_en_clair_refuse(nom_hote):
    controleur = testinfra.get_host("local://")
    url = f"http://{nom_hote}.par1.medisphere.internal:{PORT}/metrics"
    code = controleur.check_output("curl -s -o /dev/null -w '%%{http_code}' --max-time 10 %s || true", url)
    assert code == "400", f"HTTP en clair : code {code} (400 attendu)"
