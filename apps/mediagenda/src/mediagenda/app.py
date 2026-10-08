"""Application FastAPI de MédiAgenda."""

from __future__ import annotations

import logging
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta
from datetime import time as heure
from zoneinfo import ZoneInfo

from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import JSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from .cache import Cache, CacheValkey
from .config import Settings
from .depot import ConflitCreneau, Depot, DepotPostgres
from .modeles import Creneaux, RendezVous, RendezVousCreation

journal = logging.getLogger("mediagenda")
journal_acces = logging.getLogger("mediagenda.acces")

# Métriques Prometheus. Le libellé « route » est le modèle de chemin
# (/api/v1/rendez-vous/{rdv_id}), jamais le chemin réel : sinon chaque
# identifiant créerait une nouvelle série (explosion de cardinalité).
REQUETES = Counter(
    "mediagenda_http_requests_total",
    "Requêtes HTTP traitées",
    ["methode", "route", "code"],
)
DUREES = Histogram(
    "mediagenda_http_request_duration_seconds",
    "Durée de traitement des requêtes HTTP",
    ["methode", "route"],
)
CACHE = Counter(
    "mediagenda_cache_total",
    "Consultations du cache des créneaux",
    ["resultat"],  # hit, miss, erreur
)

# Plages d'ouverture du cabinet (heure locale) et pas des créneaux.
PLAGES = ((heure(8, 0), heure(12, 0)), (heure(14, 0), heure(18, 0)))
PAS = timedelta(minutes=30)
ROUTES_SONDES = {"/sante", "/pret", "/metrics"}


def create_app(
    settings: Settings,
    depot: Depot | None = None,
    cache: Cache | None = None,
) -> FastAPI:
    """Fabrique l'application. ``depot`` et ``cache`` sont injectables (tests)."""

    @asynccontextmanager
    async def cycle_de_vie(app: FastAPI) -> AsyncIterator[None]:
        app.state.depot = depot if depot is not None else DepotPostgres(settings.db_url)
        app.state.cache = cache if cache is not None else CacheValkey(settings.valkey_url)
        journal.info("démarrage", extra={"version": settings.version})
        yield
        # Exécuté à l'arrêt : uvicorn a reçu SIGTERM, a cessé d'accepter des
        # connexions et a laissé finir les requêtes en cours.
        journal.info("arrêt : fermeture des connexions")
        app.state.depot.fermer()
        app.state.cache.fermer()

    app = FastAPI(title="MédiAgenda", version=settings.version, lifespan=cycle_de_vie)
    fuseau = ZoneInfo(settings.fuseau)

    @app.middleware("http")
    async def mesurer(request: Request, call_next):
        debut = time.perf_counter()
        code = 500
        try:
            reponse = await call_next(request)
            code = reponse.status_code
            return reponse
        finally:
            duree = time.perf_counter() - debut
            route = getattr(request.scope.get("route"), "path", "non-routee")
            REQUETES.labels(request.method, route, str(code)).inc()
            DUREES.labels(request.method, route).observe(duree)
            # Une ligne par requête. Jamais de donnée patient dans le journal (RGPD).
            niveau = logging.DEBUG if route in ROUTES_SONDES else logging.INFO
            journal_acces.log(
                niveau,
                "requête",
                extra={
                    "methode": request.method,
                    "chemin": request.url.path,
                    "route": route,
                    "code": code,
                    "duree_ms": round(duree * 1000, 2),
                    "client": request.client.host if request.client else None,
                },
            )

    @app.get("/sante")
    def sante() -> dict[str, str]:
        """Vivacité : le processus répond. Ne touche à aucune dépendance."""
        return {"statut": "ok", "version": settings.version}

    @app.get("/pret")
    def pret(request: Request) -> JSONResponse:
        """Disponibilité : PostgreSQL et Valkey répondent, sinon 503."""
        etats: dict[str, str] = {}
        for nom, dependance in (
            ("postgresql", request.app.state.depot),
            ("valkey", request.app.state.cache),
        ):
            try:
                dependance.ping()
                etats[nom] = "ok"
            except Exception as exc:
                journal.warning(
                    "dépendance indisponible", extra={"dependance": nom, "erreur": str(exc)}
                )
                etats[nom] = "indisponible"
        pret_ = all(v == "ok" for v in etats.values())
        return JSONResponse(
            {"statut": "pret" if pret_ else "pas-pret", **etats},
            status_code=200 if pret_ else 503,
        )

    @app.get("/metrics")
    def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @app.get("/api/v1/rendez-vous")
    def lister(request: Request, limite: int = Query(100, ge=1, le=1000)) -> list[RendezVous]:
        return request.app.state.depot.lister(limite)

    @app.post("/api/v1/rendez-vous", status_code=201)
    def creer(request: Request, rdv: RendezVousCreation) -> RendezVous:
        try:
            cree = request.app.state.depot.creer(rdv)
        except ConflitCreneau:
            raise HTTPException(409, "créneau déjà pris pour ce praticien") from None
        _invalider(request.app.state.cache, cree)
        journal.info("rendez-vous créé", extra={"rdv_id": cree.id, "praticien": cree.praticien})
        return cree

    @app.get("/api/v1/rendez-vous/{rdv_id}")
    def obtenir(request: Request, rdv_id: int) -> RendezVous:
        rdv = request.app.state.depot.obtenir(rdv_id)
        if rdv is None:
            raise HTTPException(404, "rendez-vous introuvable")
        return rdv

    @app.delete("/api/v1/rendez-vous/{rdv_id}", status_code=204)
    def supprimer(request: Request, rdv_id: int) -> Response:
        rdv = request.app.state.depot.supprimer(rdv_id)
        if rdv is None:
            raise HTTPException(404, "rendez-vous introuvable")
        _invalider(request.app.state.cache, rdv)
        journal.info("rendez-vous supprimé", extra={"rdv_id": rdv_id})
        return Response(status_code=204)

    @app.get("/api/v1/creneaux")
    def creneaux(
        request: Request,
        jour: date = Query(alias="date", description="Jour au format AAAA-MM-JJ"),
        praticien: str = Query("tous", min_length=1, max_length=100),
    ) -> Creneaux:
        """Créneaux libres d'un jour. Résultat mis en cache dans Valkey (60 s par défaut)."""
        cache: Cache = request.app.state.cache
        cle = cle_creneaux(praticien, jour)
        try:
            en_cache = cache.lire(cle)
        except Exception as exc:
            # Cache en panne : on sert quand même, depuis la base (mode dégradé).
            journal.warning("cache indisponible", extra={"erreur": str(exc)})
            CACHE.labels("erreur").inc()
            en_cache = None
        else:
            CACHE.labels("hit" if en_cache is not None else "miss").inc()
        if en_cache is not None:
            return Creneaux.model_validate_json(en_cache)

        resultat = calculer_creneaux(request.app.state.depot, praticien, jour, fuseau)
        try:
            cache.ecrire(cle, resultat.model_dump_json(), settings.cache_ttl)
        except Exception as exc:
            journal.warning("écriture en cache impossible", extra={"erreur": str(exc)})
        return resultat

    def _invalider(cache: Cache, rdv: RendezVous) -> None:
        """Un rendez-vous créé ou supprimé change les créneaux de son jour."""
        jour = rdv.debut.astimezone(fuseau).date()
        for praticien in (rdv.praticien, "tous"):
            try:
                cache.effacer(cle_creneaux(praticien, jour))
            except Exception as exc:
                journal.warning("invalidation du cache impossible", extra={"erreur": str(exc)})

    return app


def cle_creneaux(praticien: str, jour: date) -> str:
    return f"mediagenda:creneaux:{praticien}:{jour.isoformat()}"


def calculer_creneaux(depot: Depot, praticien: str, jour: date, fuseau: ZoneInfo) -> Creneaux:
    """Liste les débuts de créneaux libres. Simplification assumée : un créneau
    est pris si un rendez-vous commence exactement à cette heure."""
    debut_jour = datetime.combine(jour, heure(0, 0), fuseau)
    fin_jour = debut_jour + timedelta(days=1)
    filtre = None if praticien == "tous" else praticien
    occupes = {d.astimezone(fuseau) for d in depot.debuts_occupes(filtre, debut_jour, fin_jour)}
    libres = []
    for ouverture, fermeture in PLAGES:
        courant = datetime.combine(jour, ouverture, fuseau)
        limite = datetime.combine(jour, fermeture, fuseau)
        while courant < limite:
            if courant not in occupes:
                libres.append(courant)
            courant += PAS
    return Creneaux(date=jour, praticien=praticien, fuseau=str(fuseau), libres=libres)
