#!/usr/bin/env python3
"""demo_sous_processus.py — délais, groupes de processus et signaux (M02-E30).

Usage : python3 demo_sous_processus.py [1|2|3|4]
  1  subprocess.run(timeout=…) avec shell=True : que devient le petit-enfant ?
  2  même chose avec une nouvelle session et os.killpg
  3  SIGTERM reçu par un Python sans gestionnaire : le bloc finally s'exécute-t-il ?
  4  même chose avec un gestionnaire de SIGTERM
Chaque cas affiche ce qu'il observe ; lis le code avant de le lancer.
"""

import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def restants(motif: str) -> list[int]:
    """PID des processus dont la ligne de commande vaut exactement `motif`."""
    pids = []
    for p in Path("/proc").iterdir():
        if p.name.isdigit():
            try:
                cmd = (p / "cmdline").read_bytes().replace(b"\0", b" ").strip()
            except OSError:
                continue
            if cmd.decode(errors="replace") == motif:
                pids.append(int(p.name))
    return pids


def menage(motif: str) -> None:
    for pid in restants(motif):
        os.kill(pid, signal.SIGKILL)


def cas1() -> None:
    try:
        subprocess.run("sleep 301; echo fini", shell=True, timeout=2, check=False)
    except subprocess.TimeoutExpired:
        print("TimeoutExpired levée après 2 s.")
    time.sleep(0.3)
    print("« sleep 301 » encore vivant :", restants("sleep 301"))
    menage("sleep 301")


def cas2() -> None:
    proc = subprocess.Popen(
        ["bash", "-c", "sleep 302; echo fini"], start_new_session=True
    )
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        print(f"délai dépassé : SIGTERM au groupe {proc.pid}")
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait()
    time.sleep(0.3)
    print("« sleep 302 » encore vivant :", restants("sleep 302"))
    menage("sleep 302")


def enfant(avec_gestionnaire: bool) -> None:
    if avec_gestionnaire:

        def gestionnaire(signum, _frame):
            raise SystemExit(128 + signum)

        signal.signal(signal.SIGTERM, gestionnaire)
    try:
        print("  enfant : travail en cours…", flush=True)
        time.sleep(60)
    finally:
        print("  enfant : bloc finally exécuté (nettoyage)", flush=True)


def cas_signal(avec_gestionnaire: bool) -> None:
    arg = "enfant-gere" if avec_gestionnaire else "enfant-brut"
    proc = subprocess.Popen([sys.executable, __file__, arg])
    time.sleep(1)
    proc.send_signal(signal.SIGTERM)
    print("code retour de l'enfant :", proc.wait())


if __name__ == "__main__":
    choix = sys.argv[1] if len(sys.argv) > 1 else "1"
    if choix == "enfant-brut":
        enfant(False)
    elif choix == "enfant-gere":
        enfant(True)
    else:
        {
            "1": cas1,
            "2": cas2,
            "3": lambda: cas_signal(False),
            "4": lambda: cas_signal(True),
        }[choix]()
