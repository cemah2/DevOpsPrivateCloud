"""Fixtures communes des tests de medictl (M02-E18).

Principe : aucun test ne parle au vrai Proxmox.
- Tests de la CLI : un FauxClient (même interface que ClientPVE) remplace
  medictl.cli.fabriquer_client ; il enregistre les écritures demandées.
- Tests du client HTTP : la bibliothèque « responses » intercepte requests
  (donc proxmoxer) et sert des réponses préparées.
- La configuration vient d'un fichier jetable (tmp_path), jamais de ~/.config.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from typer.testing import CliRunner

from medictl import cli
from medictl.erreurs import VmIntrouvable

DONNEES = Path(__file__).parent / "donnees"
SECRET = "00000000-test-test-test-secret000000"
UPID = "UPID:pve01:0000A1B2:00C0FFEE:6720F00D:{type}:{vmid}:wb-automation@pve!lab:"


@pytest.fixture
def ressources() -> list[dict]:
    return json.loads((DONNEES / "cluster-resources.json").read_text(encoding="utf-8"))


class FauxClient:
    """Double de ClientPVE : données des fixtures, écritures journalisées."""

    def __init__(self, ressources: list[dict]) -> None:
        self.ressources = ressources
        self.appels: list[tuple] = []
        self.vmids_pris = {r["vmid"] for r in ressources}
        self.tache_en_echec: str | None = None

    # lectures
    def vms(self) -> list[dict]:
        return sorted((r for r in self.ressources if r["type"] == "qemu"), key=lambda r: r["vmid"])

    def vm(self, vmid: int) -> dict:
        for r in self.vms():
            if r["vmid"] == vmid:
                return r
        raise VmIntrouvable(f"VM {vmid} introuvable (inexistante, ou hors du pool lab)")

    def config(self, vm: dict) -> dict:
        return {"name": vm["name"], "cores": 1, "memory": "1024", "net0": "virtio,bridge=vsandbox"}

    def etat(self, vm: dict) -> dict:
        return {"status": vm["status"], "uptime": 3600, "agent": 1}

    def vmid_libre(self, vmid: int) -> bool:
        return vmid not in self.vmids_pris

    def adresses_ipv4(self, vm: dict) -> list[str]:
        return []

    # tâches
    def attendre_tache(self, upid: str, **_: object) -> None:
        self.appels.append(("attendre", upid))
        if self.tache_en_echec and self.tache_en_echec in upid:
            from medictl.erreurs import ErreurApi

            raise ErreurApi(f"tâche en échec (simulé) : {upid}")

    def attendre_agent(self, vm: dict, **_: object) -> None:
        self.appels.append(("agent", vm["vmid"]))

    # écritures
    def cloner(self, source: dict, vmid: int, nom: str, pool: str) -> str:
        self.appels.append(("cloner", source["vmid"], vmid, nom, pool))
        return UPID.format(type="qmclone", vmid=source["vmid"])

    def configurer(self, noeud: str, vmid: int, **parametres: object) -> str | None:
        self.appels.append(("configurer", vmid, parametres))
        return None

    def demarrer(self, noeud: str, vmid: int) -> str:
        self.appels.append(("demarrer", vmid))
        return UPID.format(type="qmstart", vmid=vmid)

    def arreter(self, noeud: str, vmid: int) -> str:
        self.appels.append(("arreter", vmid))
        return UPID.format(type="qmstop", vmid=vmid)

    def detruire(self, noeud: str, vmid: int) -> str:
        self.appels.append(("detruire", vmid))
        return UPID.format(type="qmdestroy", vmid=vmid)

    def ecritures(self) -> list[str]:
        return [a[0] for a in self.appels if a[0] not in ("attendre", "agent")]


@pytest.fixture
def faux_client(ressources, monkeypatch) -> FauxClient:
    client = FauxClient(ressources)
    monkeypatch.setattr(cli, "fabriquer_client", lambda: client)
    return client


@pytest.fixture
def runner() -> CliRunner:
    return CliRunner()


@pytest.fixture
def fichier_env(tmp_path, monkeypatch) -> Path:
    """Fichier d'accès jetable (mode 600) ; variables PVE_* de l'appelant neutralisées."""
    ca = tmp_path / "ca.pem"
    ca.write_text("-----BEGIN CERTIFICATE-----\nfactice\n-----END CERTIFICATE-----\n")
    chemin = tmp_path / "pve-api.env"
    chemin.write_text(
        "# fichier de test\n"
        'PVE_API_URL="https://pve.test:8006/api2/json"\n'
        'PVE_NODE="pve01"              # nom du nœud\n'
        "PVE_TOKEN_ID='wb-automation@pve!lab'\n"
        f'PVE_TOKEN_SECRET="{SECRET}"\n'
        f'PVE_CACERT="$HOME/ca.pem"\n',
        encoding="utf-8",
    )
    chemin.chmod(0o600)
    for cle in ("PVE_API_URL", "PVE_NODE", "PVE_TOKEN_ID", "PVE_TOKEN_SECRET", "PVE_CACERT"):
        monkeypatch.delenv(cle, raising=False)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("MEDICTL_ENV_FILE", str(chemin))
    return chemin
