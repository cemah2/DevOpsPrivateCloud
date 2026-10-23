# mediagenda/api — src/mediagenda/app.py (EXTRAIT M29-E23, DEV-3013) : remplace la fonction pret de create_app.
    @app.get("/pret")
    def pret(request: Request) -> JSONResponse:
        """Disponibilité : 503 seulement si PostgreSQL ne répond pas.

        Valkey est un cache : sans lui, l'API sert quand même (créneaux calculés depuis la base,
        mode dégradé). Le faire entrer dans la disponibilité sortait TOUS les pods du Service à la
        moindre coupure du cache (M29-E13, INC-5623) : son état est seulement rapporté.
        """
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
        pret_ = etats["postgresql"] == "ok"
        statut = "pas-pret" if not pret_ else ("pret" if etats["valkey"] == "ok" else "degrade")
        return JSONResponse({"statut": statut, **etats}, status_code=200 if pret_ else 503)

