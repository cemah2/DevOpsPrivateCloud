"""Reprises avec délai exponentiel (M02-E17).

On ne reprend que ce qui peut réussir au deuxième essai ET ne fait pas de dégât
si le premier essai avait en fait abouti :
- erreurs réseau (connexion refusée, coupure, délai dépassé) et réponses 5xx ;
- jamais une erreur TLS (un certificat refusé le sera encore), jamais une 4xx
  (jeton refusé, droits insuffisants, paramètre invalide : il faut corriger) ;
- le client ne passe ici que les LECTURES (GET, idempotentes) : un POST de
  clonage repris après une coupure pourrait créer deux VMs.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Callable

import requests
from proxmoxer import ResourceException

log = logging.getLogger(__name__)


def est_transitoire(exc: BaseException) -> bool:
    """Vrai si l'erreur mérite un nouvel essai."""
    if isinstance(exc, requests.exceptions.SSLError):
        return False  # sous-classe de ConnectionError : à tester AVANT
    if isinstance(exc, (requests.exceptions.ConnectionError, requests.exceptions.Timeout)):
        return True
    if isinstance(exc, ResourceException):
        # 501 = méthode inexistante : permanente. 5xx (dont 595/596 de pveproxy) : transitoire.
        return exc.status_code >= 500 and exc.status_code != 501
    return False


def avec_reprises[T](
    fonction: Callable[[], T],
    *,
    nom: str,
    tentatives: int = 4,
    delai: float = 1.0,
    facteur: float = 2.0,
    dormir: Callable[[float], None] = time.sleep,
) -> T:
    """Appelle ``fonction`` ; en cas d'erreur transitoire, réessaie après 1 s, 2 s, 4 s…

    ``dormir`` est injectable : les tests vérifient les délais sans attendre.
    """
    for essai in range(1, tentatives + 1):
        try:
            return fonction()
        except Exception as exc:
            if not est_transitoire(exc) or essai == tentatives:
                raise
            attente = delai * facteur ** (essai - 1)
            log.warning(
                "%s : erreur transitoire (%s), essai %d/%d, nouvel essai dans %.1f s",
                nom,
                type(exc).__name__,
                essai,
                tentatives,
                attente,
            )
            dormir(attente)
    raise AssertionError("inaccessible")  # pragma: no cover
