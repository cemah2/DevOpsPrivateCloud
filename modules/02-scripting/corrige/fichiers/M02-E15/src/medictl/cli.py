"""Point d'entrée de la CLI — version M02-E15 : lister et décrire les VMs.

  medictl --version
  medictl vm list [--pool lab] [--format table|json]
  medictl vm show VMID [--format table|json]

Codes de sortie : 0 succès, 1 erreur (message sur stderr), 2 usage (Typer).
La configuration et la connexion viennent de medictl.pve (M02-E08).
"""

from enum import StrEnum
from typing import Annotated

import requests
import typer
from proxmoxer import ResourceException

from medictl import __version__
from medictl.pve import ConfigError, charger_config, connexion
from medictl.sortie import COLONNES_VM, en_json, en_tableau, resume_vm

app = typer.Typer(
    help="Inventaire et cycle de vie des VMs du lab MédiSphère.",
    no_args_is_help=True,
    add_completion=False,
)
vm_app = typer.Typer(help="Inventaire des VMs visibles par le jeton.", no_args_is_help=True)
app.add_typer(vm_app, name="vm")


class Format(StrEnum):
    table = "table"
    json = "json"


def _afficher_version(demande: bool) -> None:
    if demande:
        typer.echo(f"medictl {__version__}")
        raise typer.Exit()


@app.callback()
def principal(
    version: Annotated[
        bool,
        typer.Option(
            "--version",
            callback=_afficher_version,
            is_eager=True,
            help="Affiche la version et quitte.",
        ),
    ] = False,
) -> None:
    """medictl : outillage Python de l'équipe Plateforme."""


def _echec(message: str) -> typer.Exit:
    typer.echo(f"medictl : {message}", err=True)
    return typer.Exit(1)


def _ressources_vm(pve) -> list[dict]:
    """Un seul appel : /cluster/resources?type=vm. Le jeton ne voit que le pool lab."""
    ressources = pve.cluster.resources.get(type="vm")
    return sorted((r for r in ressources if r.get("type") == "qemu"), key=lambda r: r["vmid"])


@vm_app.command("list")
def vm_list(
    pool: Annotated[str | None, typer.Option(help="Ne garder que les VMs de ce pool.")] = None,
    fmt: Annotated[Format, typer.Option("--format", "-f", help="Format de sortie.")] = Format.table,
) -> None:
    """Liste les VMs visibles par le jeton."""
    try:
        vms = [resume_vm(r) for r in _ressources_vm(connexion(charger_config()))]
    except ConfigError as exc:
        raise _echec(f"configuration : {exc}") from None
    except (ResourceException, requests.exceptions.RequestException) as exc:
        raise _echec(f"API Proxmox : {exc}") from None
    if pool:
        vms = [v for v in vms if v["pool"] == pool]
    typer.echo(en_json(vms) if fmt is Format.json else en_tableau(vms, COLONNES_VM))


@vm_app.command("show")
def vm_show(
    vmid: Annotated[int, typer.Argument(help="VMID de la VM.")],
    fmt: Annotated[Format, typer.Option("--format", "-f", help="Format de sortie.")] = Format.table,
) -> None:
    """Décrit une VM : ressources et configuration."""
    try:
        pve = connexion(charger_config())
        ressource = next((r for r in _ressources_vm(pve) if r["vmid"] == vmid), None)
        if ressource is None:
            raise _echec(f"VM {vmid} introuvable (inexistante, ou hors du pool lab)")
        detail = resume_vm(ressource)
        detail["config"] = pve.nodes(ressource["node"]).qemu(vmid).config.get()
    except ConfigError as exc:
        raise _echec(f"configuration : {exc}") from None
    except (ResourceException, requests.exceptions.RequestException) as exc:
        raise _echec(f"API Proxmox : {exc}") from None
    if fmt is Format.json:
        typer.echo(en_json(detail))
        return
    for cle, valeur in detail.items():
        if cle != "config":
            typer.echo(f"{cle:12} {valeur}")
    typer.echo("config :")
    for cle in sorted(detail["config"]):
        typer.echo(f"  {cle:12} {detail['config'][cle]}")
