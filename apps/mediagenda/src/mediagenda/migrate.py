"""Migrations SQL versionnées, à la manière de Flyway.

Usage : ``python -m mediagenda.migrate [--repertoire migrations] [--statut]``

- Les fichiers s'appellent ``V<version>__<description>.sql`` (V1__init.sql,
  V2__index.sql, V2_1__ajout.sql…) et sont appliqués par version croissante.
- Chaque migration appliquée est notée dans la table ``mediagenda_historique_schema``
  avec l'empreinte SHA-256 de son contenu. Une migration déjà appliquée dont le
  fichier a changé arrête tout (on ne réécrit pas l'histoire : on ajoute une V suivante).
- Chaque fichier est appliqué dans une transaction (PostgreSQL sait rendre le DDL
  transactionnel) : en cas d'erreur, rien de ce fichier n'est appliqué.
- Un verrou consultatif (``pg_advisory_lock``) empêche deux exécutions simultanées,
  par exemple deux pods qui démarrent en même temps.

Ce n'est pas Flyway (pas de migrations « R__ », pas de retour arrière) : le
format des fichiers est le même, on peut donc passer à Flyway plus tard.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import logging
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import psycopg

from . import journal as journalisation

journal = logging.getLogger("mediagenda.migrate")

MOTIF = re.compile(r"^V(?P<version>\d+(?:_\d+)*)__(?P<description>\w+)\.sql$")
TABLE = "mediagenda_historique_schema"
VERROU = 727_465_001  # identifiant arbitraire du verrou consultatif


class ErreurMigration(Exception):
    pass


@dataclass(frozen=True)
class Migration:
    version: tuple[int, ...]
    description: str
    chemin: Path
    empreinte: str

    @property
    def version_texte(self) -> str:
        return ".".join(str(n) for n in self.version)


def decouvrir(repertoire: Path) -> list[Migration]:
    """Liste les migrations du répertoire, triées par version."""
    if not repertoire.is_dir():
        raise ErreurMigration(f"répertoire de migrations introuvable : {repertoire}")
    migrations = []
    for chemin in repertoire.iterdir():
        if chemin.suffix != ".sql":
            continue
        m = MOTIF.match(chemin.name)
        if m is None:
            raise ErreurMigration(
                f"nom de fichier non conforme (V<n>__<description>.sql) : {chemin.name}"
            )
        contenu = chemin.read_bytes()
        migrations.append(
            Migration(
                version=tuple(int(n) for n in m["version"].split("_")),
                description=m["description"],
                chemin=chemin,
                empreinte=hashlib.sha256(contenu).hexdigest(),
            )
        )
    migrations.sort(key=lambda mig: mig.version)
    for precedente, suivante in itertools.pairwise(migrations):
        if precedente.version == suivante.version:
            raise ErreurMigration(
                f"version en double : {precedente.chemin.name} et {suivante.chemin.name}"
            )
    return migrations


def a_appliquer(migrations: list[Migration], appliquees: dict[str, str]) -> list[Migration]:
    """Compare au journal ``{version: empreinte}`` et renvoie ce qui reste à faire."""
    restantes = []
    for mig in migrations:
        empreinte = appliquees.get(mig.version_texte)
        if empreinte is None:
            restantes.append(mig)
        elif empreinte != mig.empreinte:
            raise ErreurMigration(
                f"la migration V{mig.version_texte} déjà appliquée a été modifiée "
                f"({mig.chemin.name}) : crée plutôt une nouvelle version"
            )
    connues = {m.version_texte for m in migrations}
    inconnues = sorted(set(appliquees) - connues)
    if inconnues:
        raise ErreurMigration(
            f"versions appliquées absentes du répertoire : {', '.join(inconnues)}"
        )
    return restantes


def migrer(url: str, repertoire: Path) -> list[Migration]:
    """Applique les migrations manquantes et renvoie celles qui ont été appliquées."""
    migrations = decouvrir(repertoire)
    with psycopg.connect(url, autocommit=True, connect_timeout=5) as conn:
        conn.execute("SELECT pg_advisory_lock(%s)", (VERROU,))
        try:
            conn.execute(
                f"CREATE TABLE IF NOT EXISTS {TABLE} ("
                " version text PRIMARY KEY,"
                " description text NOT NULL,"
                " empreinte text NOT NULL,"
                " appliquee_le timestamptz NOT NULL DEFAULT now())"
            )
            appliquees = dict(conn.execute(f"SELECT version, empreinte FROM {TABLE}").fetchall())  # noqa: S608
            restantes = a_appliquer(migrations, appliquees)
            for mig in restantes:
                journal.info("application", extra={"migration": mig.chemin.name})
                with conn.transaction():
                    conn.execute(mig.chemin.read_text(encoding="utf-8"))
                    conn.execute(
                        f"INSERT INTO {TABLE} (version, description, empreinte) VALUES (%s, %s, %s)",  # noqa: S608
                        (mig.version_texte, mig.description, mig.empreinte),
                    )
            return restantes
        finally:
            conn.execute("SELECT pg_advisory_unlock(%s)", (VERROU,))


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="python -m mediagenda.migrate", description=__doc__.splitlines()[0]
    )
    parser.add_argument(
        "--repertoire",
        type=Path,
        default=Path(os.environ.get("MEDIAGENDA_MIGRATIONS_DIR", "migrations")),
        help="répertoire des fichiers V<n>__*.sql (défaut : $MEDIAGENDA_MIGRATIONS_DIR ou ./migrations)",
    )
    parser.add_argument(
        "--statut", action="store_true", help="affiche les migrations sans rien appliquer"
    )
    args = parser.parse_args(argv)
    journalisation.configurer(
        os.environ.get("MEDIAGENDA_LOG_LEVEL", "INFO").upper(),
        os.environ.get("MEDIAGENDA_LOG_FORMAT", "json").lower(),
    )
    try:
        if args.statut:
            for mig in decouvrir(args.repertoire):
                print(f"V{mig.version_texte}\t{mig.description}\t{mig.empreinte[:12]}")
            return
        url = os.environ.get("MEDIAGENDA_DB_URL")
        if not url:
            raise ErreurMigration("MEDIAGENDA_DB_URL absente")
        faites = migrer(url, args.repertoire)
    except (ErreurMigration, psycopg.Error) as exc:
        journal.critical("échec des migrations : %s", exc)
        sys.exit(1)
    journal.info("migrations terminées", extra={"appliquees": [m.chemin.name for m in faites]})


if __name__ == "__main__":
    main()
