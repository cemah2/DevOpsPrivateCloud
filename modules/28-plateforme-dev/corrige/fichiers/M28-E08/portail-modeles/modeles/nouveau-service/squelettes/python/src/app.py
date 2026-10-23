"""${{ values.nom }} — service minimal (squelette du modèle « nouveau service »).

Bibliothèque standard seulement : sert /sante et /pret sur le port 8080, journalise en JSON.
Remplace ce fichier par ton application (FastAPI, etc.) en gardant les deux sondes.
"""

import json
import signal
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Gestionnaire(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 (nom imposé par http.server)
        if self.path in ("/sante", "/pret"):
            corps = json.dumps({"statut": "ok"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(corps)))
            self.end_headers()
            self.wfile.write(corps)
        else:
            self.send_error(404)

    def log_message(self, format, *args):  # noqa: A002
        sys.stdout.write(json.dumps({"message": format % args, "service": "${{ values.nom }}"}) + "\n")


def main():
    serveur = ThreadingHTTPServer(("0.0.0.0", 8080), Gestionnaire)  # noqa: S104 (conteneur)
    signal.signal(signal.SIGTERM, lambda *_: serveur.shutdown())
    serveur.serve_forever()


if __name__ == "__main__":
    main()
