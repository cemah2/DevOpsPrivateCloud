"""Point d'entrée de la CLI."""

from typing import Annotated

import typer

from medictl import __version__

app = typer.Typer(
    help="Inventaire et cycle de vie des VMs du lab MédiSphère.",
    no_args_is_help=True,
    add_completion=False,
)


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
