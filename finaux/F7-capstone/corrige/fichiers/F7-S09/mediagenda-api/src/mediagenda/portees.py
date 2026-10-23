"""Contrôle des portées OAuth 2.0 des clients hébergés (F7-S09, DEV-3709).

Activé par ``MEDIAGENDA_PORTEES=oui`` (instances des clients seulement : les cabinets de MédiSphère
n'envoient pas de jeton et ne sont pas concernés, la variable est absente de leurs overlays).

Où se fait l'authentification : PAS ici. Les requêtes n'atteignent l'API qu'à travers un des deux
mandataires OAuth2 Proxy de l'espace (politique réseau ``mediagenda-depuis-mandataires``) :
  - ``oauth2-proxy-dpi`` : vérifie la signature, l'émetteur, l'audience et l'expiration du jeton
    « client credentials » du DPI, et le transmet tel quel (en-tête Authorization) ;
  - ``oauth2-proxy-agents`` : session d'un agent fédéré (F7-S08), transmet son jeton d'identité
    (``pass_authorization_header``), qui porte la revendication ``groups``.
Ce module ne revérifie donc pas la signature (le mandataire l'a fait) : il lit les revendications du
jeton déjà vérifié et applique la règle du contrat du GHSV (annexe A1) :
  - lecture (GET) : portée ``rdv:lecture`` ;
  - écriture (POST, PATCH, DELETE) : portée ``rdv:ecriture`` ;
  - un agent (groupe des agents du client, ``MEDIAGENDA_GROUPE_AGENTS``) a les deux.
Sans jeton : 401 ; jeton sans la portée : 403. Les sondes (/sante, /pret, /metrics) et la description
de l'API (/openapi.json, /docs) ne sont pas concernées.
"""

from __future__ import annotations

import base64
import binascii
import json
from collections.abc import Awaitable, Callable

from fastapi import Request, Response
from fastapi.responses import JSONResponse

LECTURE = "rdv:lecture"
ECRITURE = "rdv:ecriture"
METHODES_ECRITURE = {"POST", "PATCH", "PUT", "DELETE"}
PREFIXE_PROTEGE = "/api/"


def revendications(autorisation: str | None) -> dict | None:
    """Charge utile d'un jeton « Bearer » JWT, sans vérification de signature (faite en amont).
    ``None`` si l'en-tête est absent ou illisible."""
    if not autorisation or not autorisation.lower().startswith("bearer "):
        return None
    parties = autorisation.split(" ", 1)[1].strip().split(".")
    if len(parties) != 3:
        return None
    charge = parties[1] + "=" * (-len(parties[1]) % 4)
    try:
        donnees = json.loads(base64.urlsafe_b64decode(charge))
    except (binascii.Error, ValueError, UnicodeDecodeError):
        return None
    return donnees if isinstance(donnees, dict) else None


def portee_requise(methode: str) -> str:
    return ECRITURE if methode.upper() in METHODES_ECRITURE else LECTURE


def autorise(rev: dict, requise: str, groupe_agents: str) -> bool:
    portees = set(str(rev.get("scope", "")).split())
    groupes = rev.get("groups") or []
    if isinstance(groupes, str):
        groupes = [groupes]
    return requise in portees or groupe_agents in groupes


def intergiciel_portees(
    groupe_agents: str,
) -> Callable[[Request, Callable[[Request], Awaitable[Response]]], Awaitable[Response]]:
    """Intergiciel HTTP à enregistrer par ``app.middleware("http")`` quand les portées sont exigées."""

    async def verifier(
        request: Request, call_next: Callable[[Request], Awaitable[Response]]
    ) -> Response:
        if not request.url.path.startswith(PREFIXE_PROTEGE):
            return await call_next(request)
        rev = revendications(request.headers.get("authorization"))
        if rev is None:
            return JSONResponse(
                {"detail": "authentification requise"},
                status_code=401,
                headers={"WWW-Authenticate": "Bearer"},
            )
        if not autorise(rev, portee_requise(request.method), groupe_agents):
            return JSONResponse({"detail": "portée insuffisante"}, status_code=403)
        return await call_next(request)

    return verifier
