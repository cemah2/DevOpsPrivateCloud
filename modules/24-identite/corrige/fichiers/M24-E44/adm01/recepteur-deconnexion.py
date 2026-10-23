"""recepteur-deconnexion.py — récepteur TEMPORAIRE de déconnexion par canal arrière (M24-E44).

À copier dans le dossier personnel d'admin sur idp01 et à lancer dans une session tmux :
    python3 -I ~/recepteur-deconnexion.py
Écoute 127.0.0.1:18081 SEULEMENT (Keycloak l'appelle depuis idp01 même), affiche le corps de chaque
POST (le formulaire « logout_token=… »), répond 200. Bibliothèque standard seulement. À arrêter et
supprimer à la fin de l'exercice (le contrôle vérifie que plus rien n'écoute sur 18081).
Le logout_token affiché est un jeton signé : il ne donne aucun accès, mais il ne se recopie pas en
entier dans un compte rendu (extraits tronqués).
"""

from http.server import BaseHTTPRequestHandler, HTTPServer
from datetime import datetime


class Recepteur(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802 (nom imposé par http.server)
        longueur = int(self.headers.get("Content-Length", "0") or 0)
        corps = self.rfile.read(min(longueur, 65536)).decode("utf-8", "replace")
        print(f"{datetime.now():%H:%M:%S} POST {self.path} — {longueur} octets : {corps}", flush=True)
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, format, *args):  # noqa: A002 — silence du journal par défaut
        return


if __name__ == "__main__":
    print("Récepteur de déconnexion sur http://127.0.0.1:18081 (Ctrl-C pour arrêter)", flush=True)
    HTTPServer(("127.0.0.1", 18081), Recepteur).serve_forever()
