"""consultation — service de téléconsultation de MédiVisio (F2-S04, DEV-3204 ; métriques et secret en F2-S05).

Créé par le modèle « Nouveau service » v2 du portail (squelette Python), puis complété par l'équipe :
  GET /sante                     vivacité (toujours 200 si le processus répond)
  GET /pret                      disponibilité : 503 tant que la clé de signature des salles manque
  GET /api/v1/disponibilites     créneaux de téléconsultation FACTICES (aucune donnée de santé)
  POST /api/v1/salles            ouvre une salle factice et renvoie un lien signé (HMAC-SHA256)
  GET /metrics                   métriques Prometheus (format texte 0.0.4), écrites sans bibliothèque

Bibliothèque standard seulement (le squelette n'a pas de dépendance : pas de fichier de verrou à tenir).
Configuration par l'environnement :
  CONSULTATION_CLE_SALLES   clé HMAC des liens de salle (Secret « consultation », ExternalSecret depuis
                            kv/medivisio/<environnement>/consultation, champ cle_salles) — jamais journalisée
  CONSULTATION_ENVIRONNEMENT dev | recette | prod (journaux, en-tête de réponse)
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICE = "medivisio-consultation"
ENVIRONNEMENT = os.environ.get("CONSULTATION_ENVIRONNEMENT", "inconnu")
ROUTES_CONNUES = ("/sante", "/pret", "/metrics", "/api/v1/disponibilites", "/api/v1/salles")
SEAUX = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5)

_verrou = threading.Lock()
_requetes: dict[tuple[str, str, str], int] = {}
_durees: dict[tuple[str, str], list[float]] = {}  # (méthode, route) → [compte par seau…, +Inf, somme]


def _cle() -> bytes | None:
    valeur = os.environ.get("CONSULTATION_CLE_SALLES", "")
    return valeur.encode() if valeur else None


def _route(chemin: str) -> str:
    """Étiquette de route BORNÉE (jamais le chemin brut : un chemin inventé créerait une série)."""
    chemin = chemin.split("?", 1)[0]
    return chemin if chemin in ROUTES_CONNUES else "autre"


def _mesurer(methode: str, route: str, code: int, duree: float) -> None:
    with _verrou:
        cle = (methode, route, str(code))
        _requetes[cle] = _requetes.get(cle, 0) + 1
        h = _durees.setdefault((methode, route), [0.0] * (len(SEAUX) + 2))
        for i, borne in enumerate(SEAUX):
            if duree <= borne:
                h[i] += 1
        h[len(SEAUX)] += 1
        h[len(SEAUX) + 1] += duree


def _metriques() -> str:
    lignes = [
        "# HELP consultation_http_requests_total Requêtes HTTP traitées, par méthode, route et code.",
        "# TYPE consultation_http_requests_total counter",
    ]
    with _verrou:
        for (methode, route, code), n in sorted(_requetes.items()):
            lignes.append(f'consultation_http_requests_total{{methode="{methode}",route="{route}",code="{code}"}} {n}')
        lignes += [
            "# HELP consultation_http_request_duration_seconds Durée de traitement des requêtes HTTP.",
            "# TYPE consultation_http_request_duration_seconds histogram",
        ]
        for (methode, route), h in sorted(_durees.items()):
            etiq = f'methode="{methode}",route="{route}"'
            for i, borne in enumerate(SEAUX):
                lignes.append(f'consultation_http_request_duration_seconds_bucket{{{etiq},le="{borne}"}} {int(h[i])}')
            lignes.append(f'consultation_http_request_duration_seconds_bucket{{{etiq},le="+Inf"}} {int(h[len(SEAUX)])}')
            lignes.append(f"consultation_http_request_duration_seconds_count{{{etiq}}} {int(h[len(SEAUX)])}")
            lignes.append(f"consultation_http_request_duration_seconds_sum{{{etiq}}} {h[len(SEAUX) + 1]:.6f}")
    lignes.append(f'consultation_info{{environnement="{ENVIRONNEMENT}"}} 1')
    return "\n".join(lignes) + "\n"


class Gestionnaire(BaseHTTPRequestHandler):
    server_version = "consultation"
    sys_version = ""

    def _repondre(self, code: int, corps: dict | str, type_contenu: str = "application/json") -> None:
        donnees = (json.dumps(corps) if isinstance(corps, dict) else corps).encode()
        self.send_response(code)
        self.send_header("Content-Type", type_contenu)
        self.send_header("Content-Length", str(len(donnees)))
        self.send_header("X-Environnement", ENVIRONNEMENT)
        self.end_headers()
        self.wfile.write(donnees)
        self._code = code

    def _traiter(self, methode: str) -> None:
        debut = time.monotonic()
        self._code = 500
        route = _route(self.path)
        try:
            if methode == "GET" and route == "/sante":
                self._repondre(200, {"statut": "ok"})
            elif methode == "GET" and route == "/pret":
                if _cle() is None:
                    self._repondre(503, {"statut": "configuration incomplète"})
                else:
                    self._repondre(200, {"statut": "ok"})
            elif methode == "GET" and route == "/metrics":
                self._repondre(200, _metriques(), "text/plain; version=0.0.4")
            elif methode == "GET" and route == "/api/v1/disponibilites":
                maintenant = int(time.time() // 900 * 900)
                creneaux = [{"debut": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(maintenant + 900 * i)), "duree_min": 15}
                            for i in range(1, 9)]
                self._repondre(200, {"creneaux": creneaux})
            elif methode == "POST" and route == "/api/v1/salles":
                cle = _cle()
                if cle is None:
                    self._repondre(503, {"erreur": "service non configuré"})
                else:
                    salle = secrets.token_hex(8)
                    signature = hmac.new(cle, salle.encode(), hashlib.sha256).hexdigest()
                    self._repondre(201, {"salle": salle, "lien": f"/salles/{salle}?sig={signature}"})
            else:
                self._repondre(404, {"erreur": "inconnu"})
        finally:
            if route != "/metrics":
                _mesurer(methode, route, self._code, time.monotonic() - debut)

    def do_GET(self) -> None:  # noqa: N802 (nom imposé par http.server)
        self._traiter("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._traiter("POST")

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        # Une ligne JSON par requête : jamais d'en-tête, jamais de corps (données personnelles, clé).
        sys.stdout.write(json.dumps({"service": SERVICE, "environnement": ENVIRONNEMENT, "message": format % args}) + "\n")


def main() -> None:
    serveur = ThreadingHTTPServer(("0.0.0.0", 8080), Gestionnaire)  # noqa: S104 (conteneur)
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=serveur.shutdown).start())
    serveur.serve_forever()


if __name__ == "__main__":
    main()
