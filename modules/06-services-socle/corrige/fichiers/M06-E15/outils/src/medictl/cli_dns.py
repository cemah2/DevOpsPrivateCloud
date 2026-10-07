"""Sous-commande « medictl dns » (M06-E15).

  medictl dns sync [--dry-run]     zones PowerDNS générées depuis l'IPAM de NetBox

Lecture NetBox : le jeton en lecture suffit (MEDICTL_NETBOX_TOKEN_FILE=…/netbox-checks.token
ou mieux, un jeton de lecture propre à l'outil). Écriture : API de PowerDNS (powerdns.py).

Codes de sortie : 0 succès, 1 erreur, 4 conflits signalés (rien n'a été écrit pour eux) :
une exécution planifiée qui échoue en 4 alerte sans bloquer les autres enregistrements.
"""

from __future__ import annotations

import logging
from typing import Annotated

import typer

from medictl import journal, synchro_dns
from medictl.netbox import ClientNetbox, charger_config_netbox
from medictl.powerdns import ClientPdns, charger_config_pdns

log = logging.getLogger(__name__)

dns_app = typer.Typer(help="DNS du socle généré depuis NetBox (M06).", no_args_is_help=True)

CODE_CONFLITS = 4


def fabriquer_clients() -> tuple[ClientNetbox, ClientPdns]:
    """Point d'injection : les tests remplacent cette fonction."""
    cfg_nb, cfg_pdns = charger_config_netbox(), charger_config_pdns()
    journal.masquer(cfg_nb.jeton)
    journal.masquer(cfg_pdns.cle)
    return ClientNetbox.depuis_config(cfg_nb), ClientPdns.depuis_config(cfg_pdns)


@dns_app.command("sync")
def sync(
    dry_run: Annotated[
        bool, typer.Option("--dry-run", "-n", help="Calcule et affiche, n'écrit rien.")
    ] = False,
    adopter: Annotated[
        list[str] | None,
        typer.Option(
            "--adopter",
            help="Nom sans propriétaire (écrit à la main) à adopter. Répétable.",
        ),
    ] = None,
) -> None:
    """Crée, met à jour ou supprime les A et PTR que NetBox décrit (et seulement ceux-là)."""
    from medictl.cli import erreurs_propres  # import tardif : cli.py importe ce module

    with erreurs_propres():
        netbox, pdns = fabriquer_clients()
        ips = netbox.lister("ipam/ip-addresses/", status="active")
        attendus, anomalies = synchro_dns.voulus(ips)
        zones = {}
        for nom in (*synchro_dns.ZONES_DIRECTES, *synchro_dns.ZONES_INVERSES.values()):
            zones[nom] = pdns.zone(nom)
        plan = synchro_dns.planifier(attendus, zones, set(adopter or []))

        for ligne in plan.resume:
            typer.echo(ligne)
        for ligne in anomalies + plan.conflits:
            typer.echo(f"[conflit]   {ligne}", err=True)

        if dry_run:
            typer.echo(f"simulation : {len(plan.resume)} changement(s) prévu(s)", err=True)
        else:
            for zone, rrsets in plan.a_ecrire.items():
                pdns.modifier_rrsets(zone, rrsets)
            typer.echo(f"DNS à jour : {len(plan.resume)} changement(s)", err=True)
        if anomalies or plan.conflits:
            raise typer.Exit(CODE_CONFLITS)
