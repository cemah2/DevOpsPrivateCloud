"""Export nocturne des définitions RabbitMQ (M27-E15, PLAT-2815).

Lit GET /api/definitions (étiquette administrator exigée pour l'export de toute la grappe), RETIRE les
empreintes de mots de passe (les utilisateurs sont déclarés dans Git par le Topology Operator, leurs mots
de passe sont dans OpenBao : une sauvegarde n'a pas à les porter), et écrit un fichier JSON horodaté
dans /travail. Le conteneur suivant du Job le dépose sur s3-01. Bibliothèque standard seulement.
"""

from __future__ import annotations

import base64
import json
import os
import ssl
import sys
import urllib.request
from datetime import datetime, timezone


def main() -> int:
    url = os.environ.get("RABBITMQ_URL", "https://rabbitmq.messagerie.svc:15671").rstrip("/")
    utilisateur = os.environ["RABBITMQ_UTILISATEUR"]
    mot_de_passe = os.environ["RABBITMQ_MOT_DE_PASSE"]
    contexte = ssl.create_default_context(cafile=os.environ.get("CA", "/etc/racine/ca.crt"))
    jeton = base64.b64encode(f"{utilisateur}:{mot_de_passe}".encode()).decode()
    requete = urllib.request.Request(
        url + "/api/definitions",
        headers={"Authorization": f"Basic {jeton}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(requete, timeout=30, context=contexte) as reponse:
        definitions = json.load(reponse)

    for compte in definitions.get("users", []):
        compte.pop("password_hash", None)
        compte.pop("hashing_algorithm", None)
    definitions["medisphere_export"] = {
        "date": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "remarque": "empreintes de mots de passe retirées ; utilisateurs et permissions : plateforme/donnees",
    }

    horodatage = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    chemin = f"/travail/definitions-{horodatage}.json"
    with open(chemin, "w", encoding="utf-8") as fichier:
        json.dump(definitions, fichier, ensure_ascii=False, indent=1, sort_keys=True)
    resume = {
        "fichier": chemin,
        "vhosts": len(definitions.get("vhosts", [])),
        "files": len(definitions.get("queues", [])),
        "politiques": len(definitions.get("policies", [])),
        "version": definitions.get("rabbitmq_version"),
    }
    print(json.dumps(resume, ensure_ascii=False), flush=True)
    if resume["vhosts"] == 0 or resume["files"] == 0:
        print("export vide : échec", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
