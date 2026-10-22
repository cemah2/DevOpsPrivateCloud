#!/usr/bin/env python3
"""outils/valider-tableaux.py — plateforme/observabilite (M21-E17, PLAT-2217).

Valide les tableaux de bord JSON de tableaux/<dossier>/*.json avant qu'Argo CD ne les publie :
  - JSON valide, objet avec un titre ;
  - « uid » présent, unique dans le dépôt, de la forme <dossier>-<nom> (minuscules, chiffres,
    tirets, 40 caractères au plus : limite de Grafana) ;
  - « id » absent ou nul (identifiant interne d'une instance de Grafana) ;
  - pas de « __inputs » (export « pour partage externe ») ;
  - toute référence à une source de données passe par une variable (${datasource}), jamais par un
    UID ou un nom codé en dur ; les variables de type « datasource » sont seules exemptées.
Bibliothèque standard seulement. Usage : python3 outils/valider-tableaux.py tableaux
Code de retour : 0 si tout est conforme, 1 sinon.
"""

import json
import pathlib
import re
import sys

DOSSIERS = {"plateforme", "mediagenda", "medidoc"}
MOTIF_UID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
MOTIF_VARIABLE = re.compile(r"^\$(\{[A-Za-z0-9_]+(:[a-z]+)?\}|[A-Za-z0-9_]+)$")


def references_sources(noeud, chemin="$"):
    """Produit (chemin, valeur) pour chaque champ « datasource » du tableau."""
    if isinstance(noeud, dict):
        for cle, valeur in noeud.items():
            if cle == "datasource":
                yield f"{chemin}.datasource", valeur
            yield from references_sources(valeur, f"{chemin}.{cle}")
    elif isinstance(noeud, list):
        for i, valeur in enumerate(noeud):
            yield from references_sources(valeur, f"{chemin}[{i}]")


def est_variable(valeur):
    return isinstance(valeur, str) and bool(MOTIF_VARIABLE.match(valeur))


def verifier(fichier, racine, uids):
    erreurs = []
    dossier = fichier.relative_to(racine).parts[0] if len(fichier.relative_to(racine).parts) > 1 else ""
    if dossier not in DOSSIERS:
        erreurs.append(f"rangé hors des dossiers d'équipe ({', '.join(sorted(DOSSIERS))})")
    try:
        tableau = json.loads(fichier.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        return [f"JSON invalide : {exc}"]
    if not isinstance(tableau, dict):
        return ["le fichier ne contient pas un objet JSON"]
    if not str(tableau.get("title", "")).strip():
        erreurs.append("titre absent")
    uid = tableau.get("uid")
    if not isinstance(uid, str) or not uid:
        erreurs.append("uid absent")
    else:
        if len(uid) > 40 or not MOTIF_UID.match(uid):
            erreurs.append(f"uid « {uid} » : minuscules, chiffres et tirets, 40 caractères au plus")
        if dossier and not uid.startswith(dossier + "-"):
            erreurs.append(f"uid « {uid} » : doit commencer par « {dossier}- »")
        if uid in uids:
            erreurs.append(f"uid « {uid} » déjà utilisé par {uids[uid]}")
        else:
            uids[uid] = str(fichier)
    if tableau.get("id") not in (None,):
        erreurs.append("« id » doit être absent ou nul (identifiant propre à une instance)")
    if "__inputs" in tableau:
        erreurs.append("« __inputs » présent : export « pour partage externe », à refaire sans")
    variables_ds = {
        v.get("name")
        for v in tableau.get("templating", {}).get("list", [])
        if isinstance(v, dict) and v.get("type") == "datasource"
    }
    if not variables_ds:
        erreurs.append("aucune variable de type « datasource » (attendue : datasource)")
    for chemin, valeur in references_sources(tableau):
        if valeur is None:
            continue
        if isinstance(valeur, dict):
            ref = valeur.get("uid")
            if ref is None or est_variable(ref):
                continue
            # Sources spéciales de Grafana (annotations intégrées, panneaux « mixtes »).
            if ref in ("grafana", "-- Grafana --", "-- Mixed --", "-- Dashboard --"):
                continue
            erreurs.append(f"{chemin} : source codée en dur (uid « {ref} ») au lieu de ${{datasource}}")
        elif not est_variable(valeur):
            erreurs.append(f"{chemin} : source codée en dur (« {valeur} ») au lieu de ${{datasource}}")
    return erreurs


def main():
    racine = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "tableaux")
    fichiers = sorted(racine.rglob("*.json"))
    if not fichiers:
        print(f"aucun tableau dans {racine}/", file=sys.stderr)
        return 1
    uids = {}
    total = 0
    for fichier in fichiers:
        erreurs = verifier(fichier, racine, uids)
        total += len(erreurs)
        etat = "OK     " if not erreurs else "ERREUR "
        print(f"{etat}{fichier}")
        for erreur in erreurs:
            print(f"         - {erreur}")
    print(f"{len(fichiers)} tableau(x), {total} erreur(s).")
    return 0 if total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
