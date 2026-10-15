"""E24-tests-evasion.py — essais d'évasion SIMPLES, lancés DANS un conteneur (M12-E24).

Fourni par l'équipe Plateforme. Python 3 de la bibliothèque standard uniquement (l'image de
MédiAgenda n'a ni shell complet, ni outils système : on ne compte que sur son interpréteur).

    admin@ctr01:~$ docker exec -i mediagenda-api-1 python - < E24-tests-evasion.py
    app@ctr02:~$  podman exec -i <CONTENEUR> python3 - < E24-tests-evasion.py

Chaque essai tente un geste qu'un attaquant ferait après avoir pris le contrôle de
l'application, et affiche « BLOQUÉ » (le conteneur l'empêche) ou « POSSIBLE ». Rien n'est
modifié hors du conteneur ; dans le conteneur, les essais réussis sont défaits aussitôt.
Ce ne sont PAS de vraies évasions (aucune faille n'est exploitée) : ce sont les marches
qu'une évasion réelle doit gravir. Code retour : nombre d'essais « POSSIBLE ».
"""

import ctypes
import errno
import os
import tempfile

libc = ctypes.CDLL(None, use_errno=True)
resultats = []


def essai(nom, fonction):
    try:
        detail = fonction()
        etat = "POSSIBLE"
    except PermissionError as exc:
        etat, detail = "BLOQUÉ", f"{exc.strerror}"
    except OSError as exc:
        if exc.errno in (errno.EPERM, errno.EACCES, errno.EROFS, errno.ENOSYS, errno.ENOENT):
            etat, detail = "BLOQUÉ", f"{exc.strerror}"
        else:
            etat, detail = "INCONNU", f"{exc}"
    resultats.append(etat)
    print(f"{etat:9} {nom:44} {detail or ''}")


def appel(nom, *args):
    """Appel système par la libc ; lève OSError avec errno si l'appel échoue."""
    r = getattr(libc, nom)(*args)
    if r == -1:
        e = ctypes.get_errno()
        raise OSError(e, os.strerror(e))
    return r


def statut(champ):
    with open("/proc/self/status") as f:
        for ligne in f:
            if ligne.startswith(champ + ":"):
                return ligne.split(":", 1)[1].strip()
    return "?"


def ecrire_racine():
    chemin = "/usr/local/bin/porte-derobee"
    with open(chemin, "w") as f:
        f.write("#!/bin/sh\n")
    os.remove(chemin)
    return "un binaire a pu être déposé dans l'image"


def devenir_root():
    os.setuid(0)
    return f"uid={os.getuid()}"


def changer_proprietaire():
    with tempfile.NamedTemporaryFile(dir="/tmp") as f:
        os.chown(f.name, 0, 0)
    return "chown vers root accepté (CAP_CHOWN)"


def creer_peripherique():
    chemin = "/tmp/disque"
    os.mknod(chemin, 0o600 | 0o060000, os.makedev(8, 0))  # bloc 8:0 = /dev/sda
    os.remove(chemin)
    return "périphérique bloc créé (CAP_MKNOD)"


def monter():
    os.makedirs("/tmp/m", exist_ok=True)
    appel("mount", b"none", b"/tmp/m", b"tmpfs", 0, None)
    appel("umount", b"/tmp/m")
    return "mount accepté (CAP_SYS_ADMIN)"


def espace_utilisateur():
    CLONE_NEWUSER = 0x10000000
    pid = os.fork()
    if pid == 0:
        try:
            appel("unshare", CLONE_NEWUSER)
            os._exit(0)
        except OSError as exc:
            os._exit(exc.errno or 1)
    _, code = os.waitpid(pid, 0)
    code = os.waitstatus_to_exitcode(code)
    if code:
        raise OSError(code, os.strerror(code))
    return "nouvel espace de noms utilisateur créé (marche vers les failles noyau)"


def tracer():
    PTRACE_TRACEME = 0
    pid = os.fork()
    if pid == 0:
        try:
            appel("ptrace", PTRACE_TRACEME, 0, None, None)
            os._exit(0)
        except OSError as exc:
            os._exit(exc.errno or 1)
    _, code = os.waitpid(pid, 0)
    code = os.waitstatus_to_exitcode(code)
    if code:
        raise OSError(code, os.strerror(code))
    return "ptrace accepté (lecture de la mémoire des autres processus du conteneur)"


def sysrq():
    with open("/proc/sysrq-trigger", "w") as f:
        f.write("h")
    return "/proc/sysrq-trigger accessible en écriture"


def executer_depot():
    d = tempfile.mkdtemp(dir="/tmp")
    chemin = os.path.join(d, "outil")
    try:
        with open(chemin, "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(chemin, 0o755)
        pid = os.fork()
        if pid == 0:
            try:
                os.execv(chemin, [chemin])
            except OSError as exc:
                os._exit(exc.errno or 1)
        _, code = os.waitpid(pid, 0)
        code = os.waitstatus_to_exitcode(code)
        if code:
            raise OSError(code, os.strerror(code))
        return "un outil téléchargé dans /tmp peut être exécuté"
    finally:
        if os.path.exists(chemin):
            os.remove(chemin)
        os.rmdir(d)


def binaires_setuid():
    trouves = []
    for racine in ("/usr/bin", "/usr/sbin", "/bin", "/sbin"):
        if not os.path.isdir(racine) or os.path.islink(racine):
            continue
        for nom in os.listdir(racine):
            try:
                st = os.stat(os.path.join(racine, nom))
            except OSError:
                continue
            if st.st_mode & 0o4000 and st.st_uid == 0:
                trouves.append(nom)
    if not trouves:
        raise OSError(errno.ENOENT, "aucun binaire setuid root dans l'image")
    if statut("NoNewPrivs") == "1":
        raise OSError(errno.EPERM, f"{len(trouves)} binaire(s) setuid neutralisé(s) par no-new-privileges")
    return f"{len(trouves)} binaire(s) setuid root utilisables : {' '.join(sorted(trouves)[:6])}"


def noyau():
    with open("/dev/kmsg") as f:
        f.readline()
    return "journal du noyau de l'hôte lisible"


print(f"Utilisateur : uid={os.getuid()} gid={os.getgid()} ; NoNewPrivs={statut('NoNewPrivs')} ;"
      f" CapEff={statut('CapEff')} ; Seccomp={statut('Seccomp')}")
essai("1. déposer un binaire dans le système de fichiers", ecrire_racine)
essai("2. devenir root (setuid 0)", devenir_root)
essai("3. donner un fichier à root (chown)", changer_proprietaire)
essai("4. créer un périphérique disque (mknod)", creer_peripherique)
essai("5. monter un système de fichiers", monter)
essai("6. créer un espace de noms utilisateur", espace_utilisateur)
essai("7. tracer un processus (ptrace)", tracer)
essai("8. écrire dans /proc/sysrq-trigger", sysrq)
essai("9. lire le journal du noyau (/dev/kmsg)", noyau)
essai("10. exécuter un outil déposé dans /tmp", executer_depot)
essai("11. s'élever par un binaire setuid", binaires_setuid)
possibles = resultats.count("POSSIBLE")
print(f"Bilan : {resultats.count('BLOQUÉ')} bloqué(s), {possibles} possible(s), {resultats.count('INCONNU')} inconnu(s)")
raise SystemExit(possibles)
