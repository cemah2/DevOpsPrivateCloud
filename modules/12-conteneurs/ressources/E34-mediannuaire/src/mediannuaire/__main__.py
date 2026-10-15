"""Point d'entrée : « mediannuaire » (serveur) ou « mediannuaire sonde » (contrôle de santé).

Arrêt propre : SIGTERM ou SIGINT arrête l'acceptation de nouvelles connexions, laisse au plus
MEDIANNUAIRE_DELAI_ARRET secondes aux requêtes en cours, puis le processus sort avec le code 0.
Le signal doit arriver à CE processus (PID 1 du conteneur, forme « exec »).

« mediannuaire sonde » interroge http://127.0.0.1:$MEDIANNUAIRE_PORT/sante et rend 0 ou 1 :
utilisable comme commande de sonde de santé dans une image sans curl ni wget.
"""

from __future__ import annotations

import json
import logging
import os
import signal
import sys
import threading
import urllib.request
from datetime import UTC, datetime

from .annuaire import Annuaire, ErreurDonnees
from .config import ErreurConfiguration, Reglages
from .serveur import creer_serveur

_STANDARD = set(vars(logging.makeLogRecord({}))) | {"message", "asctime", "taskName"}


class FormateurJson(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        ligne = {
            "horodatage": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "niveau": record.levelname,
            "journal": record.name,
            "message": record.getMessage(),
        }
        ligne.update({k: v for k, v in vars(record).items() if k not in _STANDARD and not k.startswith("_")})
        return json.dumps(ligne, ensure_ascii=False, default=str)


def configurer_journal(niveau: str = "INFO") -> None:
    gestionnaire = logging.StreamHandler(sys.stdout)
    gestionnaire.setFormatter(FormateurJson())
    logging.basicConfig(level=niveau, handlers=[gestionnaire], force=True)


def sonde() -> int:
    port = os.environ.get("MEDIANNUAIRE_PORT", "8080")
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/sante", timeout=2) as r:  # noqa: S310
            return 0 if r.status == 200 else 1
    except OSError:
        return 1


def main() -> None:
    if sys.argv[1:] == ["sonde"]:
        sys.exit(sonde())
    configurer_journal()
    log = logging.getLogger("mediannuaire")
    try:
        reglages = Reglages.depuis_env()
    except ErreurConfiguration as exc:
        log.critical("configuration invalide : %s", exc)
        sys.exit(2)
    configurer_journal(reglages.niveau_journal)
    annuaire = Annuaire(reglages.donnees, reglages.cache_dir)
    try:
        annuaire.charger()
    except ErreurDonnees as exc:
        log.critical("%s", exc)
        sys.exit(3)
    except OSError as exc:
        log.critical("cache inutilisable (%s) : %s", reglages.cache_dir, exc)
        sys.exit(3)

    serveur = creer_serveur(annuaire, reglages.port, reglages.jeton_admin, reglages.version)
    arret = threading.Event()

    def sur_signal(signum: int, _frame: object) -> None:
        log.info("signal reçu, arrêt en cours", extra={"signal": signal.Signals(signum).name})
        arret.set()

    signal.signal(signal.SIGTERM, sur_signal)
    signal.signal(signal.SIGINT, sur_signal)
    fil = threading.Thread(target=serveur.serve_forever, name="http", daemon=True)
    fil.start()
    log.info("MédiAnnuaire démarré", extra={"port": reglages.port, "version": reglages.version})
    arret.wait()
    serveur.shutdown()  # plus aucune nouvelle connexion acceptée
    # server_close() attend la fin des requêtes en cours ; on ne l'attend pas plus que le délai.
    fermeture = threading.Thread(target=serveur.server_close, name="fermeture", daemon=True)
    fermeture.start()
    fermeture.join(reglages.delai_arret)
    log.info("arrêt terminé", extra={"requetes_abandonnees": fermeture.is_alive()})
    sys.exit(0)


if __name__ == "__main__":
    main()
