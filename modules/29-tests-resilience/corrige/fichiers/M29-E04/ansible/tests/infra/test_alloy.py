"""Rôle alloy (M22-E05, étendu en M24, M25, M26) : agent Grafana Alloy des VMs Debian 13.

Le rôle ne vise que Debian 13 (il refuse le reste) : les VMs Rocky (ipa01) sont sautées.
"""

import pytest

pytestmark = pytest.mark.alloy

VERSION = "1.21.1"


@pytest.fixture(autouse=True)
def _debian_seulement(famille):
    if famille != "debian":
        pytest.skip("le rôle alloy ne vise que Debian 13")


def test_binaire_de_la_version_attendue(host):
    lien = host.file("/usr/local/bin/alloy")
    assert lien.is_symlink
    assert lien.linked_to == f"/opt/alloy/{VERSION}/alloy-linux-amd64"


def test_compte_lit_le_journal(host):
    compte = host.user("alloy")
    assert compte.exists
    assert compte.shell == "/usr/sbin/nologin"
    assert {"systemd-journal", "adm"} <= set(compte.groups)


def test_journal_persistant(host):
    # Sans /var/log/journal, le journal est en mémoire : rien ne survit à un redémarrage.
    assert host.file("/var/log/journal").is_directory


def test_configuration_protegee(host):
    with host.sudo():
        conf = host.file("/etc/alloy/config.alloy")
        assert conf.exists
        assert conf.user == "root"
        assert conf.group == "alloy"
        assert conf.mode == 0o640
        assert host.run("/usr/local/bin/alloy validate /etc/alloy/config.alloy").rc == 0


def test_service_actif_et_borne(host):
    service = host.service("alloy")
    assert service.is_running
    assert service.is_enabled
    proprietes = service.systemd_properties
    assert proprietes["User"] == "alloy"
    assert proprietes["MemoryMax"] == str(256 * 1024 * 1024)


def test_interface_locale_seulement(host):
    assert host.socket("tcp://127.0.0.1:12345").is_listening
    assert not host.socket("tcp://0.0.0.0:12345").is_listening


def test_composants_sains(host):
    code = host.check_output("curl -s -o /dev/null -w '%%{http_code}' http://127.0.0.1:12345/-/ready")
    assert code == "200"
