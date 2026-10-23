"""Tests d'infrastructure des rôles Ansible (plateforme/ansible, M29-E04, PLAT-3004).

Testinfra (pytest-testinfra 10.2) se connecte aux VMs et vérifie ce que les rôles ont LAISSÉ
sur la machine : services, fichiers, sockets, réglages du noyau. Ce n'est pas Molecule (qui
teste un rôle sur une VM jetable, M04) : ici, on teste le PARC réel, après application.

Lancement depuis la racine du projet (inventaire NetBox d'ansible.cfg, NETBOX_TOKEN exporté) :

    uv run pytest tests/infra --hosts='ansible://socle' -n 4
    uv run pytest tests/infra --hosts='ansible://dns01,ansible://dns02' -m chrony
    uv run pytest tests/infra --hosts='ssh://admin@mon01.par1.medisphere.internal' -m node_exporter

Connexion : « ansible://<motif> » lit l'inventaire d'Ansible (ansible-inventory --list) et en
tire ansible_host, ansible_user, ansible_port et ansible_become. La clé SSH n'est PAS lue dans
ansible.cfg ni dans ANSIBLE_PRIVATE_KEY_FILE : en CI, passer --ssh-identity-file.
"""

from __future__ import annotations

import json

import pytest


def pytest_configure(config: pytest.Config) -> None:
    # Les marqueurs sont aussi déclarés dans pytest.ini (--strict-markers) ; rappel ici pour
    # qui lancerait les tests depuis un autre dossier.
    for nom, aide in (
        ("durcissement", "rôle durcissement (M26)"),
        ("node_exporter", "rôle node_exporter (M21)"),
        ("alloy", "rôle alloy (M22)"),
        ("chrony", "client de temps du rôle base (M04, M06-E21, M07-E25)"),
        ("reseau", "contrôle fait depuis le contrôleur (adm01 ou runner01), pas depuis l'hôte"),
    ):
        config.addinivalue_line("markers", f"{nom}: {aide}")


@pytest.fixture(scope="module")
def variables(host) -> dict:
    """Variables Ansible de l'hôte (groupes compris) ; vide si la connexion n'est pas ansible://."""
    try:
        return host.ansible.get_variables()
    except Exception:  # backend ssh://, local:// : pas d'inventaire
        return {}


@pytest.fixture(scope="module")
def groupes(variables) -> set[str]:
    return set(variables.get("group_names", []))


@pytest.fixture(scope="module")
def nom_hote(host, variables) -> str:
    return variables.get("inventory_hostname") or host.check_output("hostname -s")


@pytest.fixture(scope="module")
def famille(host) -> str:
    """debian ou rocky (les deux familles du lab)."""
    return host.system_info.distribution


@pytest.fixture(scope="module")
def est_passerelle(groupes, nom_hote) -> bool:
    # Les passerelles servent l'heure (chrony_serveur), écoutent sur 0.0.0.0, routent.
    return "role_routeur" in groupes or nom_hote in {"gw01", "gw02"}


@pytest.fixture(scope="module")
def exceptions_durcissement(host) -> set[str] | None:
    """Règles XCCDF en exception sur l'hôte (registre machine du rôle durcissement, M26-E13).

    None si le rôle n'a pas été appliqué sur cet hôte (fichier absent) : les tests du
    durcissement sont alors sautés, pas échoués — l'application par vagues est progressive.
    """
    chemin = "/etc/medisphere/conformite/exceptions.json"
    with host.sudo():
        fichier = host.file(chemin)
        if not fichier.exists:
            return None
        contenu = json.loads(fichier.content_string)
    return {e["regle"] for e in contenu.get("exceptions", [])}


@pytest.fixture(scope="module")
def adresse_defaut(host) -> str:
    """Adresse IPv4 de l'interface de la route par défaut (celle où écoutent les agents)."""
    adresses = [a for a in host.interface.default("inet").addresses if ":" not in a]
    assert adresses, "aucune adresse IPv4 sur l'interface de la route par défaut"
    return adresses[0]
