"""Sous-commande « medictl netbox » (M06-E11).

  medictl netbox whoami                  utilisateur du jeton NetBox (contrôle d'accès)
  medictl netbox sync [--dry-run] [--format table|json]

Accès Proxmox : le fichier de M02 (MEDICTL_ENV_FILE). Pour la synchronisation, le jeton
en LECTURE suffit et doit être préféré :
  MEDICTL_ENV_FILE=~/.config/workbook/pve-lecture.env medictl netbox sync --dry-run
Accès NetBox : voir medictl/netbox.py (jeton v2 du compte d'automatisation).

Codes de sortie : 0 succès (écarts signalés compris), 1 erreur, 2 usage.
"""

from __future__ import annotations

import logging
from dataclasses import asdict
from enum import StrEnum
from typing import Annotated

import typer

from medictl import journal, synchro_netbox
from medictl.erreurs import ErreurMedictl
from medictl.netbox import ClientNetbox, charger_config_netbox
from medictl.sortie import en_json

log = logging.getLogger(__name__)

netbox_app = typer.Typer(help="NetBox, source de vérité du socle (M06).", no_args_is_help=True)

NOM_CLUSTER = "pve01"


class Format(StrEnum):
    table = "table"
    json = "json"


def fabriquer_client_netbox() -> ClientNetbox:
    """Point d'injection : les tests remplacent cette fonction par un faux client."""
    cfg = charger_config_netbox()
    journal.masquer(cfg.jeton)
    log.info("NetBox %s", cfg.url)
    return ClientNetbox.depuis_config(cfg)


@netbox_app.command("whoami")
def whoami() -> None:
    """Affiche le compte NetBox associé au jeton (vérifie aussi TLS et l'en-tête Bearer)."""
    from medictl.cli import erreurs_propres  # import tardif : cli.py importe ce module

    with erreurs_propres():
        utilisateur = fabriquer_client_netbox().qui_suis_je()
        typer.echo(utilisateur.get("username", "?"))


@netbox_app.command("sync")
def sync(
    dry_run: Annotated[
        bool, typer.Option("--dry-run", "-n", help="Calcule et affiche, n'écrit rien.")
    ] = False,
    fmt: Annotated[
        Format, typer.Option("--format", "-f", help="Format du rapport.")
    ] = Format.table,
) -> None:
    """Recopie dans NetBox l'état réel des VMs Proxmox (socle et environnements)."""
    from medictl import cli  # import tardif : cli.py importe ce module

    with cli.erreurs_propres():
        netbox = fabriquer_client_netbox()
        cluster = netbox.unique("virtualization/clusters/", name=NOM_CLUSTER)
        if cluster is None:
            raise ErreurMedictl(
                f"cluster « {NOM_CLUSTER} » absent de NetBox (modélisation, M06-E05)"
            )
        etiquettes = {t["slug"] for t in netbox.lister("extras/tags/")}
        vms_netbox = netbox.lister(
            synchro_netbox.CHEMIN_VM, cluster_id=cluster["id"], exclude="config_context"
        )

        pve = cli.fabriquer_client()
        vms_proxmox = []
        for ressource in pve.vms():
            if not synchro_netbox.a_synchroniser(ressource):
                continue
            en_marche = ressource.get("status") == "running"
            vms_proxmox.append(
                (
                    ressource,
                    pve.config(ressource),
                    pve.adresses_ipv4(ressource) if en_marche else [],
                )
            )

        changements = synchro_netbox.planifier(
            vms_proxmox, vms_netbox, cluster_id=cluster["id"], etiquettes_netbox=etiquettes
        )
        if fmt is Format.json:
            typer.echo(en_json([asdict(c) for c in changements]))
        else:
            for changement in changements:
                typer.echo(changement.resume())

        ecritures = [c for c in changements if c.action != "signaler"]
        if dry_run:
            typer.echo(
                f"simulation : {len(ecritures)} écriture(s) prévue(s), "
                f"{len(changements) - len(ecritures)} écart(s) signalé(s)",
                err=True,
            )
            return
        bilan = synchro_netbox.appliquer(netbox, changements)
        typer.echo(
            f"NetBox à jour : {bilan.crees} création(s), {bilan.modifies} modification(s), "
            f"{bilan.ecarts} écart(s) signalé(s)",
            err=True,
        )
