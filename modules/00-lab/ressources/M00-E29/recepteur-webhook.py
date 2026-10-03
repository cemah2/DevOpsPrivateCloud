#!/usr/bin/env python3
"""Récepteur HTTP minimal pour tester les notifications webhook (M00-E29).

Affiche chaque requête reçue (méthode, chemin, en-têtes, corps) sur la sortie
standard et répond 200. Aucune dépendance hors bibliothèque standard.

Usage (sur adm01) :
    python3 recepteur-webhook.py --ecoute 10.10.10.10 --port 8099

Arrêt : Ctrl+C. Outil de test uniquement : pas d'authentification, pas de TLS.
"""
import argparse
import json
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Recepteur(BaseHTTPRequestHandler):
    server_version = "recepteur-webhook/1.0"

    def _traiter(self):
        longueur = int(self.headers.get("Content-Length", 0) or 0)
        corps = self.rfile.read(longueur) if longueur else b""
        horodatage = datetime.now().isoformat(timespec="seconds")
        print(f"--- {horodatage} {self.client_address[0]} {self.command} {self.path}")
        for nom, valeur in self.headers.items():
            print(f"    {nom}: {valeur}")
        if corps:
            texte = corps.decode("utf-8", errors="replace")
            try:
                print(json.dumps(json.loads(texte), indent=2, ensure_ascii=False))
            except ValueError:
                print(texte)
        print(flush=True)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"ok\n")

    do_POST = _traiter
    do_PUT = _traiter
    do_GET = _traiter

    def log_message(self, format, *args):  # noqa: A002 - signature imposée
        pass  # journal déjà affiché par _traiter


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ecoute", default="0.0.0.0", help="adresse d'écoute")
    parser.add_argument("--port", type=int, default=8099, help="port TCP")
    args = parser.parse_args()
    print(f"Écoute sur http://{args.ecoute}:{args.port}/ (Ctrl+C pour arrêter)", flush=True)
    try:
        ThreadingHTTPServer((args.ecoute, args.port), Recepteur).serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
