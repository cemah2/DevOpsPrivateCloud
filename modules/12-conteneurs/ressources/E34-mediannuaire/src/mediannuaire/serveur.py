"""Serveur HTTP (bibliothèque standard) : API en lecture, sondes, métriques, rechargement."""

from __future__ import annotations

import hmac
import json
import logging
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from .annuaire import Annuaire, ErreurDonnees

journal = logging.getLogger("mediannuaire.acces")


class Compteurs:
    def __init__(self) -> None:
        self._verrou = threading.Lock()
        self.requetes: dict[tuple[str, int], int] = {}

    def compter(self, route: str, code: int) -> None:
        with self._verrou:
            self.requetes[(route, code)] = self.requetes.get((route, code), 0) + 1

    def texte(self, annuaire: Annuaire, version: str) -> str:
        lignes = [
            "# HELP mediannuaire_http_requests_total Requêtes HTTP traitées.",
            "# TYPE mediannuaire_http_requests_total counter",
        ]
        with self._verrou:
            for (route, code), n in sorted(self.requetes.items()):
                lignes.append(f'mediannuaire_http_requests_total{{route="{route}",code="{code}"}} {n}')
        lignes += [
            "# HELP mediannuaire_praticiens Praticiens chargés.",
            "# TYPE mediannuaire_praticiens gauge",
            f"mediannuaire_praticiens {len(annuaire.liste())}",
            "# HELP mediannuaire_info Version de l'application.",
            "# TYPE mediannuaire_info gauge",
            f'mediannuaire_info{{version="{version}"}} 1',
        ]
        return "\n".join(lignes) + "\n"


def fabriquer_gestionnaire(annuaire: Annuaire, jeton: str, version: str, compteurs: Compteurs):
    class Gestionnaire(BaseHTTPRequestHandler):
        server_version = "mediannuaire"
        timeout = 30  # un client muet ne retient pas un fil (ni l'arrêt) indéfiniment
        sys_version = ""

        def log_message(self, format: str, *args: object) -> None:  # noqa: A002
            pass  # remplacé par la ligne JSON de _repondre

        def _repondre(self, route: str, code: int, corps: object, type_mime: str = "application/json") -> None:
            debut = getattr(self, "_debut", time.monotonic())
            donnees = corps.encode() if isinstance(corps, str) else json.dumps(corps, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", f"{type_mime}; charset=utf-8")
            self.send_header("Content-Length", str(len(donnees)))
            self.end_headers()
            self.wfile.write(donnees)
            compteurs.compter(route, code)
            niveau = logging.DEBUG if route in ("/sante", "/pret", "/metrics") else logging.INFO
            journal.log(niveau, "requête", extra={
                "methode": self.command, "route": route, "code": code,
                "duree_ms": round((time.monotonic() - debut) * 1000, 1),
            })

        def do_GET(self) -> None:  # noqa: N802
            self._debut = time.monotonic()
            url = urlparse(self.path)
            if url.path == "/sante":
                self._repondre("/sante", 200, {"statut": "ok", "version": version})
            elif url.path == "/pret":
                code = 200 if annuaire.pret else 503
                self._repondre("/pret", code, {"pret": annuaire.pret, "empreinte": annuaire.empreinte})
            elif url.path == "/metrics":
                self._repondre("/metrics", 200, compteurs.texte(annuaire, version), "text/plain; version=0.0.4")
            elif url.path == "/api/v1/praticiens":
                specialite = parse_qs(url.query).get("specialite", [None])[0]
                self._repondre("/api/v1/praticiens", 200, annuaire.liste(specialite))
            elif url.path.startswith("/api/v1/praticiens/"):
                p = annuaire.detail(url.path.rsplit("/", 1)[1])
                if p:
                    self._repondre("/api/v1/praticiens/{id}", 200, p)
                else:
                    self._repondre("/api/v1/praticiens/{id}", 404, {"erreur": "praticien inconnu"})
            else:
                self._repondre("autre", 404, {"erreur": "introuvable"})

        def do_POST(self) -> None:  # noqa: N802
            self._debut = time.monotonic()
            if urlparse(self.path).path != "/admin/recharger":
                self._repondre("autre", 404, {"erreur": "introuvable"})
                return
            fourni = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
            if not hmac.compare_digest(fourni.encode(), jeton.encode()):
                self._repondre("/admin/recharger", 401, {"erreur": "jeton invalide"})
                return
            try:
                n = annuaire.charger()
            except ErreurDonnees as exc:
                self._repondre("/admin/recharger", 500, {"erreur": str(exc)})
                return
            self._repondre("/admin/recharger", 200, {"praticiens": n, "empreinte": annuaire.empreinte})

    return Gestionnaire


def creer_serveur(annuaire: Annuaire, port: int, jeton: str, version: str) -> ThreadingHTTPServer:
    serveur = ThreadingHTTPServer(("0.0.0.0", port), fabriquer_gestionnaire(annuaire, jeton, version, Compteurs()))  # noqa: S104
    # Fils non « démons » : server_close() attend les requêtes en cours (arrêt propre, borné
    # par MEDIANNUAIRE_DELAI_ARRET dans __main__).
    serveur.daemon_threads = False
    serveur.block_on_close = True
    return serveur
