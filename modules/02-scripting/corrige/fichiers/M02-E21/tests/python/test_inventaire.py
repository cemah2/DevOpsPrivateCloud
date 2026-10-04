"""Inventaire du socle (M02-E21)."""

import json

import pytest

from medictl import inventaire
from medictl.cli import app

DOCUMENT = """# Inventaire du socle

Texte rédigé par l'équipe : il ne doit jamais être modifié par l'outil.

{bloc}

## Notes

Fin du document.
"""


@pytest.fixture
def client_avec_ip(faux_client):
    adresses = {1000: ["10.10.10.1", "192.168.1.30"], 1001: ["10.10.10.10"], 1002: ["10.10.20.10"]}
    faux_client.adresses_ipv4 = lambda vm: adresses.get(vm["vmid"], [])
    return faux_client


def test_collecte_ne_garde_que_le_socle(client_avec_ip):
    entrees = inventaire.collecter(client_avec_ip)
    assert [e["vmid"] for e in entrees] == [1000, 1001, 1002, 1004, 1007]
    gw01 = entrees[0]
    assert gw01["role"] == "routeur"
    assert gw01["ipv4"] == ["10.10.10.1", "192.168.1.30"]
    assert gw01["memory_mib"] == 2048


def test_vm_arretee_sans_appel_a_l_agent(faux_client):
    faux_client.ressources[1]["status"] = "stopped"  # adm01

    def interdit(vm):
        if vm["status"] != "running":
            raise AssertionError("agent interrogé pour une VM arrêtée")
        return []

    faux_client.adresses_ipv4 = interdit
    assert inventaire.collecter(faux_client)[1]["ipv4"] == []


def test_markdown_deterministe(client_avec_ip):
    premier = inventaire.en_markdown(inventaire.collecter(client_avec_ip))
    second = inventaire.en_markdown(inventaire.collecter(client_avec_ip))
    assert premier == second
    assert premier.startswith(inventaire.DEBUT) and premier.endswith(inventaire.FIN)
    assert "| 1001 | `adm01` | bastion | running | 2 | 4096 | 32.0 | 10.10.10.10 |" in premier


def test_remplacer_bloc_preserve_le_reste():
    ancien = DOCUMENT.format(bloc=f"{inventaire.DEBUT}\nancien\n{inventaire.FIN}")
    nouveau = inventaire.remplacer_bloc(ancien, f"{inventaire.DEBUT}\nneuf\n{inventaire.FIN}")
    assert nouveau == DOCUMENT.format(bloc=f"{inventaire.DEBUT}\nneuf\n{inventaire.FIN}")


def test_remplacer_bloc_ajoute_si_absent():
    nouveau = inventaire.remplacer_bloc("# Titre\n", "BLOC")
    assert nouveau == "# Titre\n\nBLOC\n"


def test_remplacer_bloc_refuse_des_balises_incoherentes():
    with pytest.raises(ValueError, match="balises"):
        inventaire.remplacer_bloc(f"{inventaire.FIN}\n{inventaire.DEBUT}\n", "BLOC")


def test_cli_json(runner, client_avec_ip):
    resultat = runner.invoke(app, ["inventaire", "--format", "json"])
    assert resultat.exit_code == 0, resultat.output
    entrees = json.loads(resultat.stdout)
    assert {"vmid", "name", "role", "status", "ipv4", "tags"} <= set(entrees[0])


def test_cli_met_a_jour_le_fichier_une_seule_fois(runner, client_avec_ip, tmp_path):
    doc = tmp_path / "inventaire.md"
    doc.write_text(DOCUMENT.format(bloc=f"{inventaire.DEBUT}\nancien\n{inventaire.FIN}"))
    resultat = runner.invoke(app, ["inventaire", "--fichier", str(doc)])
    assert resultat.exit_code == 0
    assert "mis à jour" in resultat.stdout
    contenu = doc.read_text()
    assert "Texte rédigé par l'équipe" in contenu and "Fin du document." in contenu
    assert "10.10.20.10" in contenu
    resultat = runner.invoke(app, ["inventaire", "--fichier", str(doc)])
    assert "déjà à jour" in resultat.stdout
    assert doc.read_text() == contenu


def test_cli_sans_vm_du_socle(runner, faux_client):
    faux_client.ressources[:] = [
        r for r in faux_client.ressources if "socle" not in r.get("tags", "")
    ]
    resultat = runner.invoke(app, ["inventaire"])
    assert resultat.exit_code == 1
    assert "aucune VM" in resultat.stderr
