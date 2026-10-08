"""Format des messages de notification.

{"type": "sms", "destinataire": "+33612345678", "modele": "rappel-veille", "rendez_vous_id": 42}
{"type": "mail", "destinataire": "jeanne@exemple.fr", "modele": "confirmation", "rendez_vous_id": 42}
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass

TYPES = ("sms", "mail")
_TELEPHONE = re.compile(r"^\+?[0-9][0-9 .]{5,19}$")
_MODELE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")


class MessageInvalide(ValueError):
    """Message mal formé : inutile de le réessayer."""


@dataclass(frozen=True)
class Notification:
    type: str
    destinataire: str
    modele: str
    rendez_vous_id: int

    def destinataire_masque(self) -> str:
        """Destinataire tronqué pour les journaux (donnée personnelle : RGPD)."""
        if self.type == "mail":
            local, _, domaine = self.destinataire.partition("@")
            return f"{local[:1]}***@{domaine}"
        return "*" * max(len(self.destinataire) - 2, 0) + self.destinataire[-2:]


def analyser(corps: bytes | str) -> Notification:
    try:
        donnees = json.loads(corps)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise MessageInvalide(f"JSON illisible : {exc}") from exc
    if not isinstance(donnees, dict):
        raise MessageInvalide("le message doit être un objet JSON")

    manquants = [
        c for c in ("type", "destinataire", "modele", "rendez_vous_id") if c not in donnees
    ]
    if manquants:
        raise MessageInvalide(f"champ(s) manquant(s) : {', '.join(manquants)}")

    type_, destinataire, modele, rdv = (
        donnees["type"],
        donnees["destinataire"],
        donnees["modele"],
        donnees["rendez_vous_id"],
    )
    if type_ not in TYPES:
        raise MessageInvalide(f"type inconnu : {type_!r} (sms ou mail)")
    if not isinstance(destinataire, str):
        raise MessageInvalide("destinataire doit être une chaîne")
    if type_ == "mail" and not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", destinataire):
        raise MessageInvalide("adresse mail invalide")
    if type_ == "sms" and not _TELEPHONE.fullmatch(destinataire):
        raise MessageInvalide("numéro de téléphone invalide")
    if not isinstance(modele, str) or not _MODELE.fullmatch(modele):
        raise MessageInvalide("modele invalide (minuscules, chiffres, tirets)")
    # bool est un int en Python : on l'exclut explicitement.
    if not isinstance(rdv, int) or isinstance(rdv, bool) or rdv <= 0:
        raise MessageInvalide("rendez_vous_id doit être un entier positif")
    return Notification(type_, destinataire, modele, rdv)
