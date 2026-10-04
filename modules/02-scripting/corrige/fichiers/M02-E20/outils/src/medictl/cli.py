"""Interface en ligne de commande de medictl (Typer) — M02-E15 à E19.

  medictl [-v|-vv|-vvv] [--version]
  medictl vm list [--pool lab] [--format table|json]
  medictl vm show VMID [--format table|json]
  medictl vm create NOM --vmid N [--template 9000] [--vnet vsandbox] [--cores 1]
                    [--memory 1024] [--tags T] [--wait/--no-wait]
  medictl vm destroy VMID [--yes]
  medictl config                      configuration effective, secret masqué

Codes de sortie : 0 succès, 1 erreur, 2 usage, 3 refus d'un garde-fou.
"""

from __future__ import annotations

import logging
import sys
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime
from enum import StrEnum
from typing import Annotated

import typer

from medictl import __version__, garde_fous, journal
from medictl.config import charger_config
from medictl.erreurs import ErreurMedictl, RefusGardeFou
from medictl.pve import ClientPVE
from medictl.sortie import COLONNES_VM, en_json, en_tableau, resume_vm

log = logging.getLogger(__name__)

app = typer.Typer(
    name="medictl",
    help="Exploitation du lab MédiSphère par l'API Proxmox (jeton wb-automation@pve!lab).",
    no_args_is_help=True,
    add_completion=False,
    pretty_exceptions_enable=False,
)
vm_app = typer.Typer(help="Inventaire et cycle de vie des VMs du pool lab.", no_args_is_help=True)
app.add_typer(vm_app, name="vm")


class Format(StrEnum):
    table = "table"
    json = "json"


def fabriquer_client() -> ClientPVE:
    """Point d'injection : les tests remplacent cette fonction par un faux client."""
    cfg = charger_config()
    journal.masquer(cfg.token_secret)
    log.info("API %s, jeton %s, CA %s", cfg.api_url, cfg.token_id, cfg.cacert or "système")
    return ClientPVE.depuis_config(cfg)


@contextmanager
def erreurs_propres() -> Iterator[None]:
    """Erreur prévue → message d'une ligne sur stderr et code de sortie dédié.
    Pile d'appels seulement en mode -vv (diagnostic)."""
    try:
        yield
    except ErreurMedictl as exc:
        log.debug("détail de l'erreur", exc_info=True)
        typer.echo(f"medictl : {exc}", err=True)
        raise typer.Exit(exc.code) from exc


def _version(valeur: bool) -> None:
    if valeur:
        typer.echo(f"medictl {__version__}")
        raise typer.Exit()


@app.callback()
def principal(
    verbose: Annotated[
        int, typer.Option("--verbose", "-v", count=True, help="-v : INFO, -vv : DEBUG, -vvv : HTTP")
    ] = 0,
    version: Annotated[
        bool,
        typer.Option("--version", callback=_version, is_eager=True, help="Affiche la version."),
    ] = False,
) -> None:
    journal.configurer_journal(verbose)


@app.command("config")
def afficher_config() -> None:
    """Affiche la configuration effective (secret masqué) et l'origine de chaque valeur."""
    with erreurs_propres():
        cfg = charger_config()
        for cle, valeur in cfg.affichable().items():
            typer.echo(f"{cle}={valeur}")


@vm_app.command("list")
def vm_list(
    pool: Annotated[str | None, typer.Option(help="Ne garder que les VMs de ce pool.")] = None,
    fmt: Annotated[Format, typer.Option("--format", "-f", help="Format de sortie.")] = Format.table,
) -> None:
    """Liste les VMs visibles par le jeton."""
    with erreurs_propres():
        vms = [resume_vm(r) for r in fabriquer_client().vms()]
        if pool:
            vms = [v for v in vms if v["pool"] == pool]
        typer.echo(en_json(vms) if fmt is Format.json else en_tableau(vms, COLONNES_VM))


@vm_app.command("show")
def vm_show(
    vmid: Annotated[int, typer.Argument(help="VMID de la VM.")],
    fmt: Annotated[Format, typer.Option("--format", "-f", help="Format de sortie.")] = Format.table,
) -> None:
    """Décrit une VM : ressources, état, configuration."""
    with erreurs_propres():
        client = fabriquer_client()
        ressource = client.vm(vmid)
        etat = client.etat(ressource)
        detail = resume_vm(ressource) | {
            "uptime_s": etat.get("uptime", 0),
            "agent": bool(etat.get("agent")),
            "config": client.config(ressource),
        }
        if fmt is Format.json:
            typer.echo(en_json(detail))
            return
        for cle, valeur in detail.items():
            if cle != "config":
                typer.echo(f"{cle:12} {valeur}")
        typer.echo("config :")
        for cle in sorted(detail["config"]):
            typer.echo(f"  {cle:12} {detail['config'][cle]}")


@vm_app.command("create")
def vm_create(
    nom: Annotated[str, typer.Argument(help="Nom de la VM (nom DNS court, ex. m02-test).")],
    vmid: Annotated[int, typer.Option(help="VMID : 2000-2999 ou 5000-5999.")],
    template: Annotated[int, typer.Option(help="Template à cloner.")] = 9000,
    vnet: Annotated[str, typer.Option(help="VNet SDN de la carte réseau.")] = "vsandbox",
    cores: Annotated[int, typer.Option(min=1, max=8, help="vCPU.")] = 1,
    memory: Annotated[int, typer.Option(min=256, max=16384, help="Mémoire en Mio.")] = 1024,
    tags: Annotated[str, typer.Option(help="Étiquettes Proxmox, séparées par « ; ».")] = "",
    wait: Annotated[
        bool, typer.Option("--wait/--no-wait", help="Attendre que l'agent QEMU réponde.")
    ] = True,
) -> None:
    """Clone un template en VM jetable du pool lab, la configure et la démarre."""
    with erreurs_propres():
        # Garde-fous sans réseau d'abord : un refus ne coûte rien et ne touche à rien.
        garde_fous.verifier_nom(nom)
        garde_fous.verifier_vmid_modifiable(vmid)
        client = fabriquer_client()
        source = client.vm(template)
        garde_fous.verifier_source_clonage(source)
        if not client.vmid_libre(vmid):
            raise RefusGardeFou(f"VMID {vmid} déjà utilisé : rien n'a été modifié")

        log.info("clonage de %s vers %s (%s)", template, vmid, nom)
        client.attendre_tache(client.cloner(source, vmid, nom, garde_fous.POOL))
        noeud = source["node"]
        try:
            parametres = {
                "net0": f"virtio,bridge={vnet}",
                "ipconfig0": "ip=dhcp",
                "cores": cores,
                "memory": memory,
                "description": f"medictl {__version__}, {datetime.now():%Y-%m-%d %H:%M}",
            }
            if tags:
                parametres["tags"] = tags
            upid = client.configurer(noeud, vmid, **parametres)
            if upid:
                client.attendre_tache(upid)
            client.attendre_tache(client.demarrer(noeud, vmid))
            if wait:
                client.attendre_agent({"node": noeud, "vmid": vmid})
        except ErreurMedictl as exc:
            # La VM existe : on le dit, plutôt que de laisser croire que rien n'a eu lieu.
            raise type(exc)(
                f"{exc} — la VM {vmid} a été créée mais n'est pas prête ; "
                f"pour la supprimer : medictl vm destroy {vmid}"
            ) from exc
        typer.echo(f"VM {vmid} ({nom}) créée et démarrée{' ; agent QEMU prêt' if wait else ''}")


@vm_app.command("destroy")
def vm_destroy(
    vmid: Annotated[int, typer.Argument(help="VMID de la VM à détruire.")],
    yes: Annotated[bool, typer.Option("--yes", "-y", help="Ne pas demander confirmation.")] = False,
) -> None:
    """Arrête et détruit une VM jetable du pool lab (disques compris)."""
    with erreurs_propres():
        garde_fous.verifier_vmid_modifiable(vmid)
        client = fabriquer_client()
        ressource = client.vm(vmid)
        garde_fous.verifier_vm_modifiable(ressource)
        nom = ressource.get("name", "?")
        if not yes:
            if not sys.stdin.isatty():
                raise RefusGardeFou("confirmation impossible sans terminal : ajoute --yes")
            if not typer.confirm(f"Détruire la VM {vmid} ({nom}) et ses disques ?", default=False):
                raise RefusGardeFou("destruction annulée par l'opérateur")
        noeud = ressource["node"]
        if ressource.get("status") == "running":
            client.attendre_tache(client.arreter(noeud, vmid))
        client.attendre_tache(client.detruire(noeud, vmid))
        typer.echo(f"VM {vmid} ({nom}) détruite")
