#!/usr/bin/env python3
"""outils/secrets-dans-journal.py — cherche les secrets Vault du projet dans un journal (M04-E30).

Usage (depuis la racine du projet) :
    uv run python outils/secrets-dans-journal.py JOURNAL [JOURNAL...]

Déchiffre avec ``ansible-vault view`` (identités de ansible.cfg, donc le script client) chaque
fichier du projet entièrement chiffré par Vault, relève les valeurs des variables, puis les
cherche dans les journaux : telles quelles, ligne par ligne pour les valeurs multilignes (clés
PEM), et encodées en base64 (sortie de ``slurp``). N'affiche que des NOMS de variables, jamais
une valeur. Un fichier qu'on ne peut pas déchiffrer (identité absente, par exemple ``critique``
dans un pipeline de MR) est signalé et ignoré : ses valeurs ne peuvent pas être dans le journal.

Limites : valeurs chiffrées en ligne (``!vault |``) dans des fichiers en clair non couvertes ;
valeurs de moins de 8 caractères ignorées (trop de faux positifs) ; transformations autres
que base64 (hachage, découpage) non détectées.

Codes : 0 aucun secret trouvé · 1 au moins un secret dans un journal · 2 erreur d'usage.
"""

from __future__ import annotations

import base64
import subprocess
import sys
from pathlib import Path

import yaml

LONGUEUR_MIN = 8
LIGNE_MIN = 16
EXCLUS = {".git", ".venv", "collections", "rapports", ".cache"}


class Chargeur(yaml.SafeLoader):
    """Chargeur YAML qui tolère les étiquettes !vault et !unsafe d'Ansible."""


Chargeur.add_constructor("!vault", lambda chargeur, noeud: None)
Chargeur.add_constructor("!unsafe", lambda chargeur, noeud: chargeur.construct_scalar(noeud))


def fichiers_chiffres(racine: Path) -> list[Path]:
    trouves = []
    for chemin in sorted(racine.rglob("*")):
        if not chemin.is_file() or EXCLUS.intersection(chemin.relative_to(racine).parts):
            continue
        try:
            with chemin.open("rb") as f:
                if f.read(14) == b"$ANSIBLE_VAULT":
                    trouves.append(chemin)
        except OSError:
            continue
    return trouves


def feuilles(objet, prefixe=""):
    """Produit (nom, valeur) pour chaque valeur scalaire d'une structure YAML."""
    if isinstance(objet, dict):
        for cle, valeur in objet.items():
            yield from feuilles(valeur, f"{prefixe}.{cle}" if prefixe else str(cle))
    elif isinstance(objet, list):
        for i, valeur in enumerate(objet):
            yield from feuilles(valeur, f"{prefixe}[{i}]")
    elif objet is not None and not isinstance(objet, bool):
        yield prefixe, str(objet)


def motifs(valeur: str) -> set[str]:
    """Formes sous lesquelles un secret peut apparaître dans un journal."""
    resultat = set()
    if len(valeur) >= LONGUEUR_MIN:
        resultat.add(valeur)
        resultat.add(base64.b64encode(valeur.encode()).decode())
    if "\n" in valeur:
        for ligne in valeur.splitlines():
            ligne = ligne.strip()
            if len(ligne) >= LIGNE_MIN and not ligne.startswith("-----"):
                resultat.add(ligne)
    return resultat


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.splitlines()[2], file=sys.stderr)
        return 2
    journaux = {}
    for nom in sys.argv[1:]:
        try:
            journaux[nom] = Path(nom).read_text(encoding="utf-8", errors="replace")
        except OSError as erreur:
            print(f"Journal illisible : {nom} ({erreur.strerror})", file=sys.stderr)
            return 2

    racine = Path.cwd()
    secrets: list[tuple[str, str, set[str]]] = []
    for fichier in fichiers_chiffres(racine):
        relatif = fichier.relative_to(racine)
        vue = subprocess.run(
            ["ansible-vault", "view", str(fichier)],
            capture_output=True,
            text=True,
            check=False,
        )
        if vue.returncode != 0:
            print(f"Ignoré (non déchiffrable ici) : {relatif}", file=sys.stderr)
            continue
        try:
            donnees = yaml.load(vue.stdout, Loader=Chargeur)  # noqa: S506 (chargeur sûr dérivé)
        except yaml.YAMLError:
            # Fichier chiffré qui n'est pas du YAML (clé, certificat) : sa valeur entière.
            donnees = {str(relatif): vue.stdout}
        for nom, valeur in feuilles(donnees):
            formes = motifs(valeur)
            if formes:
                secrets.append((nom, str(relatif), formes))

    fuites = 0
    for nom_journal, texte in journaux.items():
        for nom, origine, formes in secrets:
            if any(forme in texte for forme in formes):
                fuites += 1
                print(f"FUITE : {nom} ({origine}) apparaît dans {nom_journal}", file=sys.stderr)
    if fuites:
        print(f"{fuites} secret(s) trouvé(s) : ne publie pas ce journal.", file=sys.stderr)
        return 1
    print(f"Aucun des {len(secrets)} secrets connus n'apparaît dans {len(journaux)} journal(aux).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
