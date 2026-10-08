from __future__ import annotations

import io
import json
import logging
import os
import signal
import subprocess
import sys

import pytest
from prometheus_client import REGISTRY

from medinotif.config import ErreurConfiguration, Settings
from medinotif.sources import SourceStdin, creer_source
from medinotif.traitement import ExpediteurSimule, Resultat, Traiteur

SMS = json.dumps(
    {"type": "sms", "destinataire": "+33612345678", "modele": "rappel", "rendez_vous_id": 1}
)


def compteur(type_: str, resultat: str) -> float:
    valeur = REGISTRY.get_sample_value(
        "medinotif_messages_total", {"type": type_, "resultat": resultat}
    )
    return valeur or 0.0


def test_traiteur_envoie_et_journalise_sans_donnee_personnelle(caplog):
    avant = compteur("sms", "envoye")
    with caplog.at_level(logging.INFO, logger="medinotif"):
        assert Traiteur(ExpediteurSimule(0))(SMS.encode()) is Resultat.ENVOYE
    assert compteur("sms", "envoye") == avant + 1
    enregistrement = next(r for r in caplog.records if r.message.startswith("notification"))
    assert enregistrement.destinataire == "**********78"
    assert "+33612345678" not in caplog.text


def test_traiteur_rejette_un_message_invalide():
    avant = compteur("inconnu", "invalide")
    assert Traiteur(ExpediteurSimule(0))(b"{}") is Resultat.INVALIDE
    assert compteur("inconnu", "invalide") == avant + 1


def test_traiteur_signale_un_echec_d_envoi():
    class ExpediteurEnPanne:
        def envoyer(self, notification):
            raise TimeoutError("passerelle SMS injoignable")

    assert Traiteur(ExpediteurEnPanne())(SMS.encode()) is Resultat.ECHEC


def test_source_stdin_traite_chaque_ligne():
    vus = []
    SourceStdin(io.StringIO(f"{SMS}\n\n{SMS}\n")).consommer(
        lambda corps: vus.append(corps) or Resultat.ENVOYE
    )
    assert len(vus) == 2


def test_arret_termine_le_message_en_cours():
    source = SourceStdin(io.StringIO(f"{SMS}\n{SMS}\n{SMS}\n"))
    termines = []

    def traiter(corps):
        source.arreter()  # le signal arrive pendant le traitement du 1er message
        termines.append(corps)  # ... qui va quand même jusqu'au bout
        return Resultat.ENVOYE

    source.consommer(traiter)
    assert len(termines) == 1


def test_configuration():
    assert Settings.depuis_env({"MEDINOTIF_BACKEND": "stdin"}).port_metriques == 9100
    with pytest.raises(ErreurConfiguration, match="MEDINOTIF_AMQP_URL"):
        Settings.depuis_env({})
    with pytest.raises(ErreurConfiguration, match="MEDINOTIF_BACKEND"):
        Settings.depuis_env({"MEDINOTIF_BACKEND": "pigeon"})


def test_kafka_annonce_mais_pas_encore_disponible():
    with pytest.raises(ErreurConfiguration, match="module 27"):
        creer_source(Settings(backend="kafka"))


def test_processus_complet_en_mode_stdin():
    """Lance le vrai point d'entrée, comme le ferait un conteneur."""
    env = {
        **os.environ,
        "MEDINOTIF_BACKEND": "stdin",
        "MEDINOTIF_PORT_METRIQUES": "0",  # port libre choisi par le système
        "MEDINOTIF_DELAI_ENVOI_MS": "0",
    }
    resultat = subprocess.run(
        [sys.executable, "-m", "medinotif"],
        input=f"{SMS}\nnimportequoi\n",
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=True,
    )
    lignes = [json.loads(ligne) for ligne in resultat.stdout.splitlines()]
    messages = [ligne["message"] for ligne in lignes]
    assert "notification envoyée (simulation)" in messages
    assert "message rejeté" in messages
    assert messages[-1] == "arrêt terminé"


def attendre(flux, texte: str) -> None:
    """Lit le journal du processus jusqu'à la ligne qui contient ``texte``."""
    for ligne in flux:
        if texte in ligne:
            return
    pytest.fail(f"fin du journal sans « {texte} »")


def test_sigterm_arrete_proprement_le_processus():
    env = {
        **os.environ,
        "MEDINOTIF_BACKEND": "stdin",
        "MEDINOTIF_PORT_METRIQUES": "0",
        "MEDINOTIF_DELAI_ENVOI_MS": "0",
    }
    with subprocess.Popen(
        [sys.executable, "-m", "medinotif"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
        env=env,
    ) as proc:
        assert proc.stdin is not None and proc.stdout is not None
        proc.stdin.write(SMS + "\n")
        proc.stdin.flush()
        attendre(proc.stdout, "notification envoyée")
        proc.send_signal(signal.SIGTERM)
        attendre(proc.stdout, "signal reçu")
        proc.stdin.write(SMS + "\n")  # lu après le signal : n'est pas traité
        proc.stdin.close()
        reste = proc.stdout.read()
        assert proc.wait(timeout=10) == 0
    assert "notification envoyée" not in reste
    assert "arrêt terminé" in reste
