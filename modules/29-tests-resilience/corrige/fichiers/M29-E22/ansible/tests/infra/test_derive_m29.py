"""plateforme/ansible — tests/infra/test_derive_m29.py (M29-E22, PLAT-3022).

Tests qui regardent l'état EFFECTIF plutôt que les fichiers posés par les rôles : une dérive posée à
côté des fichiers d'Ansible (un « 00-… » dans sshd_config.d, une source NTP retouchée) les fait échouer
directement, au lieu d'être vue par effet de bord. À fusionner avec les tests de M29-E04 (mêmes
conventions : hôtes de l'inventaire Ansible, sudo par host.sudo()).
"""

import re

import pytest

# Fichiers de sshd_config.d dont on connaît l'auteur (même liste que ssh_durci_fichiers_connus).
FICHIERS_SSHD_CONNUS = {
    "00-durcissement.conf",
    "01-ssh-durci.conf",
    "02-ssh-ca-hote.conf",
    "03-ssh-ca-utilisateur.conf",
    "03-pve-noeud.conf",
    "05-durcissement.conf",
    "10-medisphere.conf",
    "10-durcissement.conf",
    "50-cloud-init.conf",
}


def test_sshd_aucun_fichier_inconnu(host):
    with host.sudo():
        presents = host.run("ls -1 /etc/ssh/sshd_config.d/").stdout.split()
    inconnus = sorted(f for f in presents if f.endswith(".conf") and f not in FICHIERS_SSHD_CONNUS)
    assert inconnus == [], f"fichiers inconnus dans sshd_config.d : {inconnus}"


@pytest.mark.parametrize(
    "ligne",
    [
        "permitrootlogin no",
        "passwordauthentication no",
        "x11forwarding no",
        "maxauthtries 3",
    ],
)
def test_sshd_configuration_effective(host, ligne):
    with host.sudo():
        effectif = host.check_output("sshd -T").splitlines()
    assert ligne in effectif


def test_chrony_synchronise_sur_le_lab(host):
    suivi = host.check_output("chronyc -n tracking")
    assert re.search(r"^Leap status\s*:\s*Normal$", suivi, re.MULTILINE), suivi
    sources = host.check_output("chronyc -n sources")
    # la source choisie (^*) est dans le plan d'adressage du lab (passerelle du VLAN, PLAN §4.3 bis)
    choisies = [ligne for ligne in sources.splitlines() if ligne.startswith("^*")]
    assert choisies, sources
    assert " 10.10." in choisies[0], choisies[0]


def test_node_exporter_actif_et_active(host):
    service = host.service("node_exporter")
    assert service.is_running
    assert service.is_enabled
    # écoute sur l'adresse de l'hôte (node_exporter_adresse, M21-E08), en TLS : on regarde le port seul
    assert host.run("ss -ltnH 'sport = :9100'").stdout.strip() != ""
