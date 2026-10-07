"""CLI « medictl netbox » (M06-E11) : comportement observable, sans Proxmox ni NetBox."""

from __future__ import annotations

import json

import pytest

from medictl import cli_netbox
from medictl.cli import app


class FauxNetbox:
    """Double de ClientNetbox : un cluster, des étiquettes, les VMs déjà connues."""

    def __init__(self, vms: list[dict]) -> None:
        self.vms = vms
        self.ecritures: list[tuple] = []

    def unique(self, chemin, **filtres):
        return {"id": 1, "name": "pve01"} if chemin.startswith("virtualization/clusters") else None

    def lister(self, chemin, **filtres):
        if chemin == "extras/tags/":
            return [{"slug": s} for s in ("socle", "role-routeur", "role-bastion", "role-dns")]
        return self.vms

    def qui_suis_je(self):
        return {"username": "svc-automatisation"}

    def creer(self, chemin, donnees):
        self.ecritures.append(("POST", chemin, donnees))
        return {"id": 100}

    def modifier(self, chemin, ident, donnees):
        self.ecritures.append(("PATCH", chemin, ident, donnees))
        return {"id": ident}


@pytest.fixture
def faux_netbox(monkeypatch) -> FauxNetbox:
    faux = FauxNetbox([])
    monkeypatch.setattr(cli_netbox, "fabriquer_client_netbox", lambda: faux)
    return faux


def test_whoami(runner, faux_netbox):
    resultat = runner.invoke(app, ["netbox", "whoami"])
    assert resultat.exit_code == 0
    assert resultat.stdout.strip() == "svc-automatisation"


def test_dry_run_n_ecrit_rien(runner, faux_client, faux_netbox):
    resultat = runner.invoke(app, ["netbox", "sync", "--dry-run", "--format", "json"])
    assert resultat.exit_code == 0, resultat.output
    plan = json.loads(resultat.stdout)
    assert {c["action"] for c in plan} <= {"creer", "signaler"}
    assert any(c["nom"] == "dns01" and c["action"] == "creer" for c in plan)
    assert faux_netbox.ecritures == []
    assert faux_client.ecritures() == []  # Proxmox n'est jamais modifié
    assert "simulation" in resultat.stderr


def test_sync_ecrit_puis_second_passage_vide(runner, faux_client, faux_netbox):
    premier = runner.invoke(app, ["netbox", "sync"])
    assert premier.exit_code == 0, premier.output
    creations = [e for e in faux_netbox.ecritures if e[0] == "POST"]
    assert creations, "le premier passage doit créer les VMs du socle"

    # NetBox renvoie désormais ce qui a été créé (même forme que l'API).
    faux_netbox.vms = [
        {
            "id": i,
            "name": d["name"],
            "status": {"value": d["status"]},
            "vcpus": d["vcpus"],
            "memory": d["memory"],
            "disk": d["disk"],
            "start_on_boot": {"value": d["start_on_boot"]},
            "custom_fields": d["custom_fields"],
            "cluster": {"id": 1},
            "tags": d["tags"],
            "primary_ip4": None,
            "virtual_disk_count": 0,
        }
        for i, (_, _, d) in enumerate(creations, start=1)
    ]
    faux_netbox.ecritures.clear()
    second = runner.invoke(app, ["netbox", "sync"])
    assert second.exit_code == 0
    assert faux_netbox.ecritures == []
