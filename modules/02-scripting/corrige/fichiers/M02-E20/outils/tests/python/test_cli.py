"""CLI medictl (M02-E15, E16, E18) : comportement observable, sans Proxmox.

On vérifie ce que voit l'opérateur (stdout, stderr, code de sortie) et ce que
la commande a demandé au client (écritures), jamais l'implémentation interne.
"""

import json

import pytest

from medictl import __version__
from medictl.cli import app


def test_version(runner):
    resultat = runner.invoke(app, ["--version"])
    assert resultat.exit_code == 0
    assert resultat.stdout.strip() == f"medictl {__version__}"


def test_sans_argument_affiche_l_aide(runner):
    resultat = runner.invoke(app, [])
    assert resultat.exit_code == 2
    assert "Usage" in resultat.output


def test_option_inconnue_code_2(runner, faux_client):
    assert runner.invoke(app, ["vm", "list", "--couleur"]).exit_code == 2


# --- vm list / show -----------------------------------------------------------------


def test_vm_list_json(runner, faux_client):
    resultat = runner.invoke(app, ["vm", "list", "--format", "json"])
    assert resultat.exit_code == 0, resultat.output
    vms = json.loads(resultat.stdout)
    assert [v["vmid"] for v in vms] == [1000, 1001, 1002, 1004, 1007, 2020, 2021, 2029, 9000]
    adm01 = next(v for v in vms if v["vmid"] == 1001)
    assert adm01 == {
        "vmid": 1001,
        "name": "adm01",
        "status": "running",
        "node": "pve01",
        "pool": "lab",
        "template": False,
        "cpus": 2,
        "memory_mib": 4096,
        "disk_gib": 32.0,
        "tags": ["role-bastion", "socle"],
    }
    assert next(v for v in vms if v["vmid"] == 9000)["template"] is True


def test_vm_list_filtre_par_pool(runner, faux_client):
    resultat = runner.invoke(app, ["vm", "list", "--pool", "lab", "-f", "json"])
    assert 2029 not in [v["vmid"] for v in json.loads(resultat.stdout)]


def test_vm_list_table(runner, faux_client):
    resultat = runner.invoke(app, ["vm", "list"])
    assert resultat.exit_code == 0
    lignes = resultat.stdout.splitlines()
    assert lignes[0].split()[:3] == ["VMID", "NOM", "ÉTAT"]
    assert any(ligne.split()[:2] == ["1002", "dns01"] for ligne in lignes)


def test_vm_show_json(runner, faux_client):
    resultat = runner.invoke(app, ["vm", "show", "2020", "-f", "json"])
    assert resultat.exit_code == 0
    detail = json.loads(resultat.stdout)
    assert detail["name"] == "m02-cobaye"
    assert detail["config"]["net0"] == "virtio,bridge=vsandbox"


def test_vm_show_introuvable_code_1_message_clair(runner, faux_client):
    resultat = runner.invoke(app, ["vm", "show", "4242"])
    assert resultat.exit_code == 1
    assert "VM 4242 introuvable" in resultat.stderr
    assert resultat.stdout == ""


# --- vm create -------------------------------------------------------------------------


def test_create_nominal(runner, faux_client):
    resultat = runner.invoke(
        app, ["vm", "create", "m02-test", "--vmid", "2022", "--cores", "2", "--tags", "env-m02"]
    )
    assert resultat.exit_code == 0, resultat.output
    assert faux_client.ecritures() == ["cloner", "configurer", "demarrer"]
    assert faux_client.appels[0] == ("cloner", 9000, 2022, "m02-test", "lab")
    parametres = faux_client.appels[2][2]
    assert parametres["net0"] == "virtio,bridge=vsandbox"
    assert parametres["cores"] == 2
    assert parametres["memory"] == 1024
    assert parametres["tags"] == "env-m02"
    assert ("agent", 2022) in faux_client.appels


def test_create_no_wait_n_attend_pas_l_agent(runner, faux_client):
    resultat = runner.invoke(app, ["vm", "create", "m02-test", "--vmid", "2022", "--no-wait"])
    assert resultat.exit_code == 0
    assert not [a for a in faux_client.appels if a[0] == "agent"]


def test_create_vmid_obligatoire(runner, faux_client):
    assert runner.invoke(app, ["vm", "create", "m02-test"]).exit_code == 2


@pytest.mark.parametrize(
    "args",
    [
        ["m02-test", "--vmid", "1050"],  # socle
        ["m02-test", "--vmid", "9050"],  # templates
        ["m02-test", "--vmid", "4000"],  # hors plages
        ["M02_TEST", "--vmid", "2022"],  # nom invalide
        ["m02-test", "--vmid", "2020"],  # VMID déjà pris
        ["m02-test", "--vmid", "2022", "--template", "1002"],  # source qui n'est pas un template
    ],
)
def test_create_refus_code_3_sans_ecriture(runner, faux_client, args):
    resultat = runner.invoke(app, ["vm", "create", *args])
    assert resultat.exit_code == 3, resultat.output
    assert faux_client.ecritures() == []


def test_create_bornes_des_ressources(runner, faux_client):
    resultat = runner.invoke(app, ["vm", "create", "m02-test", "--vmid", "2022", "--memory", "64"])
    assert resultat.exit_code == 2
    assert faux_client.ecritures() == []


def test_create_echec_apres_clonage_explique_le_menage(runner, faux_client):
    faux_client.tache_en_echec = "qmstart"
    resultat = runner.invoke(app, ["vm", "create", "m02-test", "--vmid", "2022"])
    assert resultat.exit_code == 1
    assert "medictl vm destroy 2022" in resultat.stderr


# --- vm destroy -------------------------------------------------------------------------


def test_destroy_avec_yes_arrete_puis_detruit(runner, faux_client):
    resultat = runner.invoke(app, ["vm", "destroy", "2020", "--yes"])
    assert resultat.exit_code == 0, resultat.output
    assert faux_client.ecritures() == ["arreter", "detruire"]


def test_destroy_vm_arretee_pas_d_arret(runner, faux_client):
    assert runner.invoke(app, ["vm", "destroy", "2021", "-y"]).exit_code == 0
    assert faux_client.ecritures() == ["detruire"]


def test_destroy_sans_terminal_ni_yes_refuse(runner, faux_client):
    # CliRunner fournit une entrée qui n'est pas un terminal : comme cron ou la CI.
    resultat = runner.invoke(app, ["vm", "destroy", "2020"], input="o\n")
    assert resultat.exit_code == 3
    assert "--yes" in resultat.stderr
    assert faux_client.ecritures() == []


@pytest.mark.parametrize(
    ("vmid", "motif"),
    [
        ("1001", "socle"),
        ("9000", "templates"),
        ("2029", "hors du pool"),
        ("100", "hors des plages"),
    ],
)
def test_destroy_refus_code_3(runner, faux_client, vmid, motif):
    resultat = runner.invoke(app, ["vm", "destroy", vmid, "--yes"])
    assert resultat.exit_code == 3
    assert motif in resultat.stderr
    assert faux_client.ecritures() == []


def test_destroy_vm_inexistante_code_1(runner, faux_client):
    resultat = runner.invoke(app, ["vm", "destroy", "2028", "--yes"])
    assert resultat.exit_code == 1
    assert faux_client.ecritures() == []
