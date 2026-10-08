from __future__ import annotations

import json

import pytest

from medinotif.message import MessageInvalide, analyser

SMS = {
    "type": "sms",
    "destinataire": "+33612345678",
    "modele": "rappel-veille",
    "rendez_vous_id": 42,
}
MAIL = {
    "type": "mail",
    "destinataire": "jeanne.dupont@exemple.fr",
    "modele": "confirmation",
    "rendez_vous_id": 7,
}


def test_sms_valide():
    n = analyser(json.dumps(SMS).encode())
    assert (n.type, n.rendez_vous_id) == ("sms", 42)
    assert n.destinataire_masque() == "**********78"


def test_mail_valide_et_masque():
    n = analyser(json.dumps(MAIL))
    assert n.destinataire_masque() == "j***@exemple.fr"


@pytest.mark.parametrize(
    ("corps", "raison"),
    [
        (b"pas du json", "JSON illisible"),
        (b"\xff\xfe", "JSON illisible"),
        (b"[1, 2]", "objet JSON"),
        (json.dumps({"type": "sms"}).encode(), "manquant"),
        (json.dumps({**SMS, "type": "pigeon"}).encode(), "type inconnu"),
        (json.dumps({**MAIL, "destinataire": "sans-arobase"}).encode(), "mail invalide"),
        (json.dumps({**SMS, "destinataire": "appelle-moi"}).encode(), "téléphone"),
        (json.dumps({**SMS, "modele": "Rappel Veille"}).encode(), "modele"),
        (json.dumps({**SMS, "rendez_vous_id": "42"}).encode(), "rendez_vous_id"),
        (json.dumps({**SMS, "rendez_vous_id": True}).encode(), "rendez_vous_id"),
        (json.dumps({**SMS, "rendez_vous_id": 0}).encode(), "rendez_vous_id"),
    ],
)
def test_messages_invalides(corps, raison):
    with pytest.raises(MessageInvalide, match=raison):
        analyser(corps)
