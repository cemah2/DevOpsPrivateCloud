"""Premier appel à l'API Proxmox VE avec requests, certificat vérifié (M02-E08, étape 1).

Lancement, depuis la copie de travail du projet (environnement uv) :
    admin@adm01:~/src/outils$ uv run python ~/m02/e08/essai_requests.py
"""

import os
import sys
from pathlib import Path

import requests

FICHIER = Path(os.environ.get("MEDICTL_ENV_FILE", Path.home() / ".config/workbook/pve-api.env"))


def lire_env(chemin: Path) -> dict[str, str]:
    """Version volontairement minimale : CLE="valeur" ou CLE=valeur, commentaires ignorés."""
    valeurs = {}
    for ligne in chemin.read_text(encoding="utf-8").splitlines():
        ligne = ligne.strip()
        if not ligne or ligne.startswith("#") or "=" not in ligne:
            continue
        cle, _, valeur = ligne.partition("=")
        valeur = valeur.strip()
        if valeur.startswith('"'):
            valeur = valeur[1:].split('"', 1)[0]
        valeurs[cle.strip()] = os.path.expandvars(valeur)
    return valeurs


def main() -> int:
    env = lire_env(FICHIER)
    session = requests.Session()
    # L'en-tête porte le secret : il n'est jamais affiché.
    session.headers["Authorization"] = (
        f"PVEAPIToken={env['PVE_TOKEN_ID']}={env['PVE_TOKEN_SECRET']}"
    )
    # verify = chemin de l'autorité de pve01 : la chaîne ET le nom sont vérifiés.
    # Passé à chaque appel : un « session.verify » serait écrasé par les variables
    # REQUESTS_CA_BUNDLE / CURL_CA_BUNDLE si elles sont définies (piège de requests).
    autorite = env["PVE_CACERT"]

    for chemin in ("/version", "/cluster/resources?type=vm", f"/nodes/{env['PVE_NODE']}/status"):
        try:
            reponse = session.get(env["PVE_API_URL"] + chemin, verify=autorite, timeout=10)
        except requests.exceptions.SSLError as exc:
            print(f"TLS refusé pour {chemin} : {exc}", file=sys.stderr)
            return 1
        # Proxmox met le motif d'un refus dans la ligne de statut (reason).
        print(f"GET {chemin} → {reponse.status_code} {reponse.reason}")
        if reponse.ok:
            donnees = reponse.json()["data"]
            print(f"   {type(donnees).__name__} de {len(donnees)} élément(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
