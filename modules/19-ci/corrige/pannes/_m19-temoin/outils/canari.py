"""Canari de la CI MédiSphère (projet témoin formation/ci-pannes, module 19, palier 4).

Vérifie l'accès HTTPS au dépôt avec le jeton CANARI_JETON (en-tête Basic préparé par le job),
consomme CANARI_MEMOIRE_MIO Mio de mémoire et CANARI_DISQUE_MIO Mio de disque dans /tmp pendant
CANARI_DUREE secondes, puis libère tout. Aucune dépendance hors de la bibliothèque standard.
"""

import os
import ssl
import sys
import time
import urllib.error
import urllib.request

MIO = 1024 * 1024


def contexte_tls() -> ssl.SSLContext:
    """Racine MédiSphère : fichier transmis par le runner, sinon variable d'instance (M13)."""
    for var in ("CI_SERVER_TLS_CA_FILE", "MEDISPHERE_ROOT_CA"):
        chemin = os.environ.get(var, "")
        if chemin and os.path.isfile(chemin):
            return ssl.create_default_context(cafile=chemin)
    return ssl.create_default_context()


def acces_depot() -> None:
    auth = os.environ.get("CANARI_AUTH", "")
    if not auth:
        print("CANARI jeton absent (référence non protégée ?) : accès au dépôt non vérifié")
        return
    url = os.environ["CI_PROJECT_URL"] + ".git/info/refs?service=git-upload-pack"
    requete = urllib.request.Request(url, headers={"Authorization": "Basic " + auth})
    try:
        with urllib.request.urlopen(requete, context=contexte_tls(), timeout=20) as rep:
            print(f"CANARI accès au dépôt : HTTP {rep.status}")
    except urllib.error.HTTPError as err:
        print(f"CANARI accès au dépôt refusé : HTTP {err.code}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    acces_depot()
    memoire = int(os.environ.get("CANARI_MEMOIRE_MIO", "120"))
    bloc = bytearray(memoire * MIO)
    for i in range(0, len(bloc), 4096):
        bloc[i] = 1
    print(f"CANARI mémoire occupée : {memoire} Mio")
    disque = int(os.environ.get("CANARI_DISQUE_MIO", "100"))
    zeros = bytes(MIO)
    with open("/tmp/canari.bin", "wb") as fichier:
        for _ in range(disque):
            fichier.write(zeros)
        fichier.flush()
        os.fsync(fichier.fileno())
    print(f"CANARI disque occupé : {disque} Mio dans /tmp")
    duree = int(os.environ.get("CANARI_DUREE", "45"))
    time.sleep(duree)
    os.remove("/tmp/canari.bin")
    del bloc
    print(f"CANARI terminé après {duree} s d'attente")


if __name__ == "__main__":
    main()
