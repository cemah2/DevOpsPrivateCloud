"""Tests de bin/ms-attendre (M02-E30) pilotés par subprocess.

Ils vérifient le contrat de l'outil : codes retour, délai total borné, essai bloqué
tué, et surtout le comportement face aux signaux (aucun sous-processus orphelin).
Aucun accès réseau.
"""

import os
import signal
import subprocess
import time
from pathlib import Path

import pytest

OUTIL = Path(__file__).resolve().parents[2] / "bin" / "ms-attendre"


def lancer(*args: str, delai: float = 30) -> tuple[int, float]:
    """Exécute ms-attendre jusqu'au bout ; renvoie (code retour, durée en secondes)."""
    debut = time.monotonic()
    res = subprocess.run(
        [str(OUTIL), *args], capture_output=True, text=True, timeout=delai, check=False
    )
    return res.returncode, time.monotonic() - debut


def processus_restants(motif: str) -> list[int]:
    """PID des processus dont la ligne de commande vaut exactement `motif`."""
    pids = []
    for entree in Path("/proc").iterdir():
        if not entree.name.isdigit():
            continue
        try:
            cmd = (entree / "cmdline").read_bytes().replace(b"\0", b" ").strip()
        except OSError:
            continue
        if cmd.decode(errors="replace") == motif:
            pids.append(int(entree.name))
    return pids


def test_succes_immediat():
    code, duree = lancer("--", "true")
    assert code == 0
    assert duree < 3


def test_delai_total_depasse():
    code, duree = lancer("-d", "3", "-i", "1", "--", "false")
    assert code == 1
    assert 2 <= duree < 7


def test_essai_bloque_est_tue():
    # Sans borne par essai, « sleep 30 » bloquerait 30 s : l'outil doit rendre la main.
    code, duree = lancer("-d", "4", "-i", "1", "-e", "1", "--", "sleep", "30")
    assert code == 1
    assert duree < 9


def test_usage():
    assert lancer("--delai", "abc", "--", "true")[0] == 2
    assert lancer("-d", "10")[0] == 2


@pytest.mark.parametrize(
    ("sig", "code_attendu"), [(signal.SIGTERM, 143), (signal.SIGINT, 130)]
)
def test_signal_sans_orphelin(sig, code_attendu):
    # Durée « signature » pour retrouver le sous-processus sans confusion possible.
    signature = "47.25" if sig == signal.SIGTERM else "47.75"
    # Nouvelle session : en cas d'échec, le test tue le groupe sans se tuer lui-même.
    proc = subprocess.Popen(
        [str(OUTIL), "-d", "60", "-e", "50", "--", "sleep", signature],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        time.sleep(1)
        assert processus_restants(f"sleep {signature}"), "l'essai n'a pas démarré"
        debut = time.monotonic()
        proc.send_signal(sig)
        code = proc.wait(timeout=10)
        assert code == code_attendu
        assert time.monotonic() - debut < 3, "signal non traité immédiatement"
        time.sleep(0.5)
        assert processus_restants(f"sleep {signature}") == [], "sous-processus orphelin"
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        for pid in processus_restants(f"sleep {signature}"):
            os.kill(pid, signal.SIGKILL)
