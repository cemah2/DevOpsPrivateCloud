#!/usr/bin/env python3
"""provisionner.py — de la source de vérité au serveur en service (M11-E15 ; profil k8s-noeud : F1-S06).

Usage :  uv run outils/provisionner.py <équipement> [--reprendre] [--dry-run]
         uv run outils/provisionner.py <nœud> --apres-bascule [--dry-run]     (profil k8s-noeud)

Cycle de vie (statut NetBox de l'équipement, rôle « serveur-bm ») :

    planned ──► staged (pxe_action=installer) ──► staged (pxe_action=local) ──► active
                   │  allumage, installation,       │  allumage sur le disque,
                   │  arrêt en fin d'installation   │  SSH, accueil Ansible, vérifications
                   └──────────── échec à n'importe quelle étape ──► failed (+ journal NetBox)

Profil k8s-noeud (F1-S06) : l'objet est une VM NetBox de plate-forme « k8s-noeud » (champ
personnalisé pxe_action étendu aux VMs). Même cycle, deux différences :
  - si l'adresse de SERVICE (IP primaire) est hors du réseau de provisioning (k8s-w03 : 10.10.40.63),
    l'usine s'arrête après l'installation (staged, pxe_action=local, machine éteinte) : la bascule de
    la carte du VLAN 60 au VLAN 40 appartient à OpenTofu (envs/k8s, phase « service »), qui démarre la
    VM. Ensuite « --apres-bascule » confirme la clé d'hôte par l'agent QEMU, vérifie le profil en SSH
    et passe la VM « active » (elle entre alors dans l'inventaire netbox-k8s.yml) ;
  - à la place de l'accueil Ansible des serveurs bm (accueil-bm.yml), une VÉRIFICATION du profil en SSH
    (pas de swap, eth0 à l'adresse de service, racine de la PKI, agent QEMU, nom) : la configuration
    du nœud est le travail des rôles Kubernetes (k8s-noeuds.yml, k8s-cluster.yml), pas de l'usine.
  Une machine d'essai dont l'adresse de service est DANS le VLAN 60 (f1-usine-essai) suit le cycle
  complet d'un trait.

Le champ personnalisé « pxe_action » dit au rendu (outils/netbox-provision.py, regle_installation:
pxe_action dans parametres.yml) quel script iPXE servir pour la MAC : installation si l'équipement
est « staged » avec pxe_action=installer, disque local (rendre la main au micrologiciel) dans tous
les autres cas. Un équipement active ne se réinstalle donc jamais.

La machine installée ne rappelle personne : l'orchestrateur observe ce qu'il contrôle déjà
(alimentation par l'API de Proxmox, port SSH, DNS). Aucun secret n'est posé sur la machine.

Identités (jamais en argument de ligne de commande) :
  NetBox  : NETBOX_URL (défaut https://nbx01.par1.medisphere.internal) ; jeton en écriture de
            svc-automatisation (statut, champs et journal des équipements « serveur-bm » seulement) :
            variable NETBOX_TOKEN (CI : protégée et masquée), à défaut fichier NETBOX_TOKEN_FILE
            (défaut ~/.config/workbook/netbox-auto.token, 600, M06-E10).
  Proxmox : fichier PVE_ENV (défaut ~/.config/workbook/pve-provision.env : PVE_API_URL, PVE_NODE,
            PVE_TOKEN_ID, PVE_TOKEN_SECRET, PVE_CACERT), jeton wb-provision@pve!provision
            (rôle WBProvision : VM.Audit, VM.PowerMgmt, VM.GuestAgent.FileRead sur /vms/2112 à
            /vms/2115 ; F1-S06 : aussi /vms/3101 le temps de l'essai et /vms/2146, k8s-w03). La lecture de fichier par l'agent QEMU sert à confirmer la clé d'hôte SSH
            par un canal qui ne passe pas par le réseau (premier contact sans « accept-new »).
Commandes externes (variables d'environnement, valeurs par défaut adaptées au lab) :
  PROVISION_RENDRE   rendu des fichiers servis par pxe01 (outils/netbox-provision.py, M11-E06/E13)
  PROVISION_PUBLIER  dépôt du rendu sur pxe01 (outils/publier.sh, M11-E03)
  PROVISION_ACCUEIL  accueil Ansible de la machine (clé d'hôte signée, racine, rôle base)
Code de retour : 0 en service (ou déjà en service), 1 échec (équipement « failed »), 2 usage.
"""

from __future__ import annotations

import argparse
import ipaddress
import os
import shlex
import socket
import subprocess
import sys
import time
from pathlib import Path

import requests

# Doit correspondre EXACTEMENT aux ACL du rôle WBProvision (registre des secrets).
VMID_AUTORISES = set(range(2112, 2116)) | {2146, 3101}
PROFIL_K8S = "k8s-noeud"
RESEAU_PROVISIONING = os.environ.get("PROVISION_RESEAU", "10.10.60.0/24")
DOMAINE = "par1.medisphere.internal"
DELAIS = {  # secondes
    "installation": int(os.environ.get("PROVISION_DELAI_INSTALLATION", "3600")),
    "demarrage": int(os.environ.get("PROVISION_DELAI_DEMARRAGE", "600")),
    "arret": 120,
}
RENDRE = os.environ.get("PROVISION_RENDRE", "uv run outils/netbox-provision.py rendre")
PUBLIER = os.environ.get("PROVISION_PUBLIER", "outils/publier.sh")
ACCUEIL = os.environ.get(
    "PROVISION_ACCUEIL",
    "uv run ansible-playbook -i inventories/lab/netbox-bm.yml playbooks/accueil-bm.yml"
    " --limit {nom} -e accueil_known_hosts={known_hosts}",
)
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "provisionner"
ANSIBLE_PROJET = os.environ.get("ANSIBLE_PROJET", str(Path(os.environ.get("WB_SRC", Path.home() / "src")) / "ansible"))


class Echec(Exception):
    """Échec d'une étape : message destiné à l'exploitant (étape, cause probable, où regarder)."""


def journal_local(message: str) -> None:
    print(f"{time.strftime('%H:%M:%S')} {message}", flush=True)


def lire_env(fichier: Path) -> dict[str, str]:
    valeurs = {}
    if fichier.stat().st_mode & 0o077:
        raise Echec(f"{fichier} doit être en 600")
    for ligne in fichier.read_text(encoding="utf-8").splitlines():
        ligne = ligne.strip()
        if ligne and not ligne.startswith("#") and "=" in ligne:
            cle, val = ligne.split("=", 1)
            valeurs[cle.strip()] = val.strip().strip('"').strip("'")
    return valeurs


class NetBox:
    def __init__(self, url: str, jeton: str, dry_run: bool):
        self.url = url.rstrip("/") + "/api"
        self.s = requests.Session()
        self.s.headers.update({"Authorization": f"Bearer {jeton}", "Accept": "application/json"})
        self.dry_run = dry_run

    def equipement(self, nom: str) -> dict:
        """Équipement (dcim.device), sinon VM du profil k8s-noeud (F1-S06). Le dictionnaire reçoit
        « _chemin » et « _type » (API et type d'objet NetBox), utilisés pour écrire."""
        for chemin, type_objet, params in (
            ("dcim/devices", "dcim.device", {"name": nom}),
            ("virtualization/virtual-machines", "virtualization.virtualmachine", {"name": nom, "platform": PROFIL_K8S}),
        ):
            r = self.s.get(f"{self.url}/{chemin}/", params=params, timeout=15)
            r.raise_for_status()
            res = r.json()["results"]
            if len(res) > 1:
                raise Echec(f"NetBox : {len(res)} objets nommés {nom} ({chemin})")
            if len(res) == 1:
                return {**res[0], "_chemin": chemin, "_type": type_objet}
        raise Echec(f"NetBox : aucun équipement serveur-bm ni VM {PROFIL_K8S} nommé {nom}")

    def modifier(self, dev: dict, **champs) -> None:
        if self.dry_run:
            journal_local(f"[dry-run] NetBox {dev['name']} : {champs}")
            return
        r = self.s.patch(f"{self.url}/{dev['_chemin']}/{dev['id']}/", json=champs, timeout=15)
        if r.status_code == 403:
            raise Echec("NetBox refuse la modification : droits de svc-automatisation (registre des secrets)")
        r.raise_for_status()

    def journal(self, dev: dict, genre: str, texte: str) -> None:
        journal_local(texte)
        if self.dry_run:
            return
        r = self.s.post(
            f"{self.url}/extras/journal-entries/",
            json={
                "assigned_object_type": dev["_type"],
                "assigned_object_id": dev["id"],
                "kind": genre,  # info, success, warning, danger
                "comments": f"[provisionner] {texte}",
            },
            timeout=15,
        )
        r.raise_for_status()


class Proxmox:
    def __init__(self, env: dict[str, str], dry_run: bool):
        self.url = env["PVE_API_URL"].rstrip("/")
        self.noeud = env["PVE_NODE"]
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"PVEAPIToken={env['PVE_TOKEN_ID']}={env['PVE_TOKEN_SECRET']}"
        self.s.verify = env["PVE_CACERT"]
        self.dry_run = dry_run

    def vmid(self, nom: str) -> int:
        r = self.s.get(f"{self.url}/cluster/resources", params={"type": "vm"}, timeout=15)
        r.raise_for_status()
        ids = [v["vmid"] for v in r.json()["data"] if v.get("name") == nom]
        if len(ids) != 1 or ids[0] not in VMID_AUTORISES:
            raise Echec(
                f"Proxmox : VM « {nom} » introuvable ou hors des VMID autorisés {sorted(VMID_AUTORISES)} ({ids})"
            )
        return ids[0]

    def etat(self, vmid: int) -> str:
        r = self.s.get(f"{self.url}/nodes/{self.noeud}/qemu/{vmid}/status/current", timeout=15)
        r.raise_for_status()
        return r.json()["data"]["status"]  # running, stopped

    def lire_fichier(self, vmid: int, chemin: str) -> str:
        """Lit un fichier de l'invité par l'agent QEMU (privilège VM.GuestAgent.FileRead)."""
        r = self.s.get(
            f"{self.url}/nodes/{self.noeud}/qemu/{vmid}/agent/file-read", params={"file": chemin}, timeout=30
        )
        r.raise_for_status()
        return r.json()["data"]["content"]

    def action(self, vmid: int, quoi: str) -> None:  # start, stop
        if self.dry_run:
            journal_local(f"[dry-run] Proxmox {vmid} : {quoi}")
            return
        r = self.s.post(f"{self.url}/nodes/{self.noeud}/qemu/{vmid}/status/{quoi}", timeout=30)
        if r.status_code in (401, 403):
            raise Echec(
                f"Proxmox refuse « {quoi} » sur {vmid} ({r.status_code}) : jeton wb-provision, rôle WBProvision"
            )
        r.raise_for_status()


def attendre(condition, delai: int, pas: int, quoi: str) -> None:
    fin = time.monotonic() + delai
    while time.monotonic() < fin:
        if condition():
            return
        time.sleep(pas)
    raise Echec(f"délai dépassé ({delai} s) : {quoi}")


def port_ouvert(ip: str, port: int) -> bool:
    try:
        with socket.create_connection((ip, port), timeout=3):
            return True
    except OSError:
        return False


def lancer(
    commande: str, quoi: str, cwd: str | None = None, dry_run: bool = False, env: dict[str, str] | None = None
) -> None:
    if dry_run:
        journal_local(f"[dry-run] {quoi} : {commande}")
        return
    # Commandes fixées par le code ou par l'exploitant (variables PROVISION_*), jamais par NetBox.
    r = subprocess.run(shlex.split(commande), cwd=cwd, env=env, check=False)  # noqa: S603
    if r.returncode != 0:
        raise Echec(f"{quoi} : « {commande} » a échoué (code {r.returncode})")


def rendre_publier(quoi: str, dry_run: bool) -> None:
    """Rend depuis NetBox (état qui vient d'être écrit) puis publie sur pxe01 : ce que sert pxe01
    pour la MAC doit avoir changé AVANT que la machine ne démarre."""
    lancer(RENDRE, f"rendu ({quoi})", dry_run=dry_run)
    lancer(PUBLIER, f"publication sur pxe01 ({quoi})", dry_run=dry_run)


def env_inventaire() -> dict[str, str]:
    """Environnement de l'accueil Ansible : l'inventaire NetBox (netbox-bm.yml) lit NETBOX_TOKEN.
    Sur adm01, c'est le jeton en LECTURE de svc-automatisation (netbox-ansible.env), pas celui de
    l'orchestrateur ; en CI, la variable du projet."""
    env = dict(os.environ)
    if not env.get("NETBOX_TOKEN"):
        fichier = Path.home() / ".config/workbook/netbox-ansible.env"
        if fichier.exists():
            env["NETBOX_TOKEN"] = lire_env(fichier).get("NETBOX_TOKEN", "")
    return env


def jeton_netbox() -> str:
    jeton = os.environ.get("NETBOX_TOKEN", "")
    if jeton:
        return jeton
    fichier = Path(os.environ.get("NETBOX_TOKEN_FILE", Path.home() / ".config/workbook/netbox-auto.token"))
    if not fichier.exists():
        return ""
    if fichier.stat().st_mode & 0o077:
        raise Echec(f"{fichier} doit être en 600")
    return fichier.read_text(encoding="utf-8").strip()


def _essai(fonction) -> bool:
    try:
        return bool(fonction())
    except requests.RequestException:
        return False


def resolu(fqdn: str, ip: str) -> bool:
    try:
        return ip in {a[4][0] for a in socket.getaddrinfo(fqdn, 22, socket.AF_INET)}
    except OSError:
        return False


def ssh_certificat_ok(nom: str) -> bool:
    """Connexion neuve, clé d'hôte vérifiée (certificat d'hôte et @cert-authority d'adm01)."""
    commande = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        "ControlPath=none",
        "-o",
        "ConnectTimeout=8",
        f"admin@{nom}.{DOMAINE}",
        "true",
    ]
    r = subprocess.run(commande, check=False, capture_output=True)  # noqa: S603
    return r.returncode == 0


def verifier_profil_k8s(nom: str, ip: str, known_hosts: Path) -> None:
    """Profil k8s-noeud : contrôles en SSH, clé d'hôte confirmée (fichier known_hosts de l'agent QEMU).
    Lecture seule sur la machine ; chaque contrôle a son message."""
    controles = [
        ("pas de swap actif", 'test -z "$(swapon --noheadings)"'),
        ("aucun swap dans fstab", "! grep -Eq '^[^#].*[[:space:]]swap[[:space:]]' /etc/fstab"),
        (f"eth0 porte {ip}", f"ip -4 -o addr show dev eth0 | grep -q ' {ip}/'"),
        ("racine de la PKI installée", "test -s /usr/local/share/ca-certificates/medisphere-root-ca.crt"),
        ("agent QEMU actif", "systemctl is-active --quiet qemu-guest-agent"),
        (f"nom d'hôte {nom}", f'test "$(hostname)" = {shlex.quote(nom)}'),
        ("installée par l'usine (profil k8s-noeud)", "grep -q ' k8s-noeud ' /etc/medisphere-usine"),
    ]
    for quoi, commande in controles:
        r = subprocess.run(  # noqa: S603
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                f"UserKnownHostsFile={known_hosts}",
                "-o",
                "StrictHostKeyChecking=yes",
                "-o",
                "ControlPath=none",
                "-o",
                "ConnectTimeout=8",
                f"admin@{ip}",
                commande,
            ],
            check=False,
            capture_output=True,
        )
        if r.returncode != 0:
            raise Echec(f"profil {PROFIL_K8S} : {quoi} — non vérifié (code {r.returncode})")


def dans_provisioning(ip: str) -> bool:
    return ipaddress.ip_address(ip) in ipaddress.ip_network(RESEAU_PROVISIONING)


def confirmer_cle(pve: Proxmox, vmid: int, nom: str, ip: str, dry_run: bool) -> Path:
    """Clé publique ED25519 lue DANS la machine par l'agent QEMU, écrite dans un known_hosts dédié."""
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    known_hosts = CACHE / f"known_hosts-{nom}"
    if not dry_run:
        attendre(
            lambda: _essai(lambda: pve.lire_fichier(vmid, "/etc/ssh/ssh_host_ed25519_key.pub")),
            120,
            10,
            "agent QEMU de la machine (paquet qemu-guest-agent, option agent de la VM)",
        )
        cle = pve.lire_fichier(vmid, "/etc/ssh/ssh_host_ed25519_key.pub").split()
        known_hosts.write_text(f"{nom},{nom}.{DOMAINE},{ip} {cle[0]} {cle[1]}\n", encoding="utf-8")
    return known_hosts


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("equipement")
    p.add_argument("--reprendre", action="store_true", help="reprendre un équipement « failed »")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument(
        "--apres-bascule",
        action="store_true",
        help=f"profil {PROFIL_K8S} : mise en service après la bascule réseau faite par OpenTofu (envs/k8s)",
    )
    a = p.parse_args()

    try:
        jeton = jeton_netbox()
    except Echec as e:
        print(e, file=sys.stderr)
        return 2
    if not jeton:
        print("Jeton NetBox absent (NETBOX_TOKEN ou ~/.config/workbook/netbox-auto.token)", file=sys.stderr)
        return 2
    nb = NetBox(os.environ.get("NETBOX_URL", "https://nbx01.par1.medisphere.internal"), jeton, a.dry_run)
    pve_env = Path(os.environ.get("PVE_ENV", Path.home() / ".config/workbook/pve-provision.env"))
    pve = Proxmox(lire_env(pve_env), a.dry_run)

    dev = nb.equipement(a.equipement)
    nom = dev["name"]
    k8s = dev["_type"] == "virtualization.virtualmachine"
    if not k8s and (dev.get("role") or {}).get("slug") != "serveur-bm":
        print(f"{nom} n'a pas le rôle serveur-bm : refus", file=sys.stderr)
        return 2
    if a.apres_bascule and not k8s:
        print(f"--apres-bascule ne concerne que le profil {PROFIL_K8S}", file=sys.stderr)
        return 2
    ip = ((dev.get("primary_ip4") or {}).get("address") or "").split("/")[0]
    statut = dev["status"]["value"]
    if not ip:
        print(f"{nom} : pas d'adresse IP primaire dans NetBox", file=sys.stderr)
        return 2

    if statut == "active":
        if port_ouvert(ip, 22) and ssh_certificat_ok(nom):
            journal_local(f"{nom} : déjà en service, rien à faire")
            return 0
        print(f"{nom} est active mais injoignable : incident d'exploitation, pas de réinstallation", file=sys.stderr)
        return 1
    if statut == "failed" and not a.reprendre:
        print(f"{nom} est en échec : analyse le journal NetBox, puis relance avec --reprendre", file=sys.stderr)
        return 1
    if statut not in ("planned", "staged", "failed"):
        print(f"{nom} : statut {statut} non géré", file=sys.stderr)
        return 2

    if a.apres_bascule:
        return apres_bascule(nb, pve, dev, nom, ip, statut, a.dry_run)

    etape = "préparation"
    try:
        vmid = pve.vmid(nom)
        action = (dev.get("custom_fields") or {}).get("pxe_action")
        # Reprise : une machine déjà installée (pxe_action=local) ne repasse pas par l'installation.
        if not (statut in ("staged", "failed") and action == "local"):
            etape = "installation"
            nb.modifier(dev, status="staged", custom_fields={"pxe_action": "installer"})
            nb.journal(dev, "info", f"{etape} : début (statut staged, script iPXE d'installation)")
            rendre_publier("installation", a.dry_run)
            if pve.etat(vmid) == "running":
                pve.action(vmid, "stop")
                attendre(lambda: pve.etat(vmid) == "stopped", DELAIS["arret"], 5, "arrêt de la VM")
            pve.action(vmid, "start")
            if not a.dry_run:
                attendre(
                    lambda: pve.etat(vmid) == "stopped",
                    DELAIS["installation"],
                    30,
                    "fin d'installation (la machine s'éteint) : regarde sa console",
                )
            nb.journal(dev, "info", f"{etape} : terminée (machine éteinte)")

        if k8s and not dans_provisioning(ip):
            # Le nœud ne peut pas démarrer ici : son adresse de service est sur un autre VLAN.
            nb.modifier(dev, status="staged", custom_fields={"pxe_action": "local"})
            rendre_publier("démarrage local", a.dry_run)
            nb.journal(
                dev,
                "info",
                f"installé et éteint ; bascule réseau attendue (envs/k8s, phase service), "
                f"puis provisionner.py {nom} --apres-bascule",
            )
            return 0

        etape = "premier démarrage"
        nb.modifier(dev, status="staged", custom_fields={"pxe_action": "local"})
        rendre_publier("démarrage local", a.dry_run)
        if pve.etat(vmid) == "stopped":
            pve.action(vmid, "start")
        if not a.dry_run:
            attendre(
                lambda: port_ouvert(ip, 22),
                DELAIS["demarrage"],
                10,
                f"SSH de {ip} (si la console montre une réinstallation : rendu « local » non déployé)",
            )
            attendre(lambda: resolu(f"{nom}.{DOMAINE}", ip), 120, 10, f"DNS {nom}.{DOMAINE} → {ip}")
        nb.journal(dev, "info", f"{etape} : SSH ouvert, nom résolu")

        etape = "clé d'hôte"
        # Clé publique lue DANS la machine par l'agent QEMU, pas sur le réseau : c'est elle
        # qu'Ansible (ou la vérification du profil) exigera de sshd au premier contact.
        known_hosts = confirmer_cle(pve, vmid, nom, ip, a.dry_run)
        nb.journal(dev, "info", f"{etape} : clé ED25519 lue par l'agent QEMU")

        if k8s:
            etape = "vérification du profil"
            if not a.dry_run:
                verifier_profil_k8s(nom, ip, known_hosts)
            nb.journal(dev, "info", f"{etape} : {PROFIL_K8S} conforme")
            etape = "mise en service"
            nb.modifier(dev, status="active", custom_fields={"pxe_action": "local"})
            rendre_publier("en service", a.dry_run)
            nb.journal(dev, "success", f"{etape} : {nom} installé par l'usine, profil vérifié ({ip})")
            return 0

        etape = "accueil Ansible"
        lancer(
            ACCUEIL.format(nom=nom, known_hosts=known_hosts),
            etape,
            cwd=ANSIBLE_PROJET,
            dry_run=a.dry_run,
            env=env_inventaire(),
        )
        if not a.dry_run and not ssh_certificat_ok(nom):
            raise Echec("clé d'hôte non reconnue après l'accueil (certificat d'hôte, @cert-authority)")
        nb.journal(dev, "info", f"{etape} : racine, clé d'hôte signée, rôle base")

        etape = "mise en service"
        nb.modifier(dev, status="active", custom_fields={"pxe_action": "local"})
        rendre_publier("en service", a.dry_run)
        nb.journal(dev, "success", f"{etape} : {nom} en service ({ip})")
        return 0
    except (Echec, requests.RequestException) as e:
        message = f"ÉCHEC à l'étape « {etape} » : {e}"
        print(message, file=sys.stderr)
        try:
            nb.modifier(dev, status="failed")
            nb.journal(dev, "danger", message)
        except (Echec, requests.RequestException) as e2:
            print(f"(et NetBox n'a pas pu être mis à jour : {e2})", file=sys.stderr)
        return 1


def apres_bascule(nb: NetBox, pve: Proxmox, dev: dict, nom: str, ip: str, statut: str, dry_run: bool) -> int:
    """Profil k8s-noeud : la VM installée a été rebranchée sur son VLAN de service et démarrée par
    OpenTofu. Clé d'hôte, vérification, statut active. Rien n'est réinstallé."""
    action = (dev.get("custom_fields") or {}).get("pxe_action")
    if statut != "staged" or action != "local":
        print(f"{nom} : attendu staged/pxe_action=local (installé, éteint), trouvé {statut}/{action}", file=sys.stderr)
        return 1
    etape = "après bascule"
    try:
        vmid = pve.vmid(nom)
        if pve.etat(vmid) != "running":
            raise Echec("la VM n'est pas démarrée : appliquer la phase « service » d'envs/k8s d'abord")
        if not dry_run:
            attendre(lambda: port_ouvert(ip, 22), DELAIS["demarrage"], 10, f"SSH de {ip} (carte sur le bon VLAN ?)")
            attendre(lambda: resolu(f"{nom}.{DOMAINE}", ip), 120, 10, f"DNS {nom}.{DOMAINE} → {ip}")
        known_hosts = confirmer_cle(pve, vmid, nom, ip, dry_run)
        etape = "vérification du profil"
        if not dry_run:
            verifier_profil_k8s(nom, ip, known_hosts)
        nb.modifier(dev, status="active", custom_fields={"pxe_action": "local"})
        rendre_publier("en service", dry_run)
        nb.journal(
            dev, "success", f"en service sur {ip} ; clé d'hôte dans {known_hosts} pour le premier contact Ansible"
        )
        return 0
    except (Echec, requests.RequestException) as e:
        message = f"ÉCHEC à l'étape « {etape} » : {e}"
        print(message, file=sys.stderr)
        try:
            nb.modifier(dev, status="failed")
            nb.journal(dev, "danger", message)
        except (Echec, requests.RequestException) as e2:
            print(f"(et NetBox n'a pas pu être mis à jour : {e2})", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
