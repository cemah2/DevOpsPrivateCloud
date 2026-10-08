#!/usr/bin/python3
"""Service de réponse de l'installateur automatique de Proxmox VE (M11-E14).

L'installateur (préparé avec « prepare-iso --fetch-from http ») envoie un POST JSON qui décrit
la machine (dont les adresses MAC de ses interfaces) avec l'en-tête
« Authorization: Bearer <nom>:<secret> ». On répond le fichier de réponse TOML de la machine.

- écoute locale seulement (nginx fait le TLS et le filtrage d'adresses) ;
- jeton comparé en temps constant, jamais journalisé ;
- 403 sans jeton valide, 404 si aucune MAC du corps n'est connue, 413 si le corps est trop gros.
Bibliothèque standard seulement (aucune dépendance sur pxe01).
"""
import hmac
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CONF = Path("/etc/pve-reponses")
REPONSES = Path("/srv/pve-answer")
CORPS_MAX = 64 * 1024
MAC_RE = re.compile(r"\b([0-9a-f]{2}(?::[0-9a-f]{2}){5})\b", re.IGNORECASE)


def charger():
    jeton = (CONF / "jeton").read_text(encoding="utf-8").strip()
    table = json.loads((CONF / "machines.json").read_text(encoding="utf-8"))
    # {"bc:24:11:00:60:04": "bm04.toml"} ; MAC normalisées en minuscules
    return jeton, {m.lower(): f for m, f in table.items()}


class Gestionnaire(BaseHTTPRequestHandler):
    server_version = "pve-reponses"
    sys_version = ""

    def log_message(self, fmt, *args):  # journal sans en-têtes (donc sans jeton)
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def _repondre(self, code, corps=b"", type_="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", type_)
        self.send_header("Content-Length", str(len(corps)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):  # noqa: N802 (nom imposé par http.server)
        self._repondre(405, b"POST attendu\n")

    def do_POST(self):  # noqa: N802
        jeton, table = charger()
        recu = self.headers.get("Authorization", "")
        attendu = "Bearer " + jeton
        if not hmac.compare_digest(recu.encode(), attendu.encode()):
            self.log_message("refus : jeton absent ou invalide")
            self._repondre(403, b"refuse\n")
            return
        taille = int(self.headers.get("Content-Length") or 0)
        if taille > CORPS_MAX:
            self._repondre(413, b"trop gros\n")
            return
        corps = self.rfile.read(taille).decode("utf-8", errors="replace")
        macs = {m.lower() for m in MAC_RE.findall(corps)}
        connues = sorted(macs & table.keys())
        if len(connues) != 1:
            self.log_message("aucune réponse : MAC reçues %s, connues %s", sorted(macs), connues)
            self._repondre(404, b"machine inconnue\n")
            return
        fichier = REPONSES / table[connues[0]]
        self.log_message("réponse %s pour %s", fichier.name, connues[0])
        self._repondre(200, fichier.read_bytes(), "application/toml")


def main():
    adresse = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8090
    ThreadingHTTPServer((adresse, port), Gestionnaire).serve_forever()


if __name__ == "__main__":
    main()
