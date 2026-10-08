#!/usr/bin/env python3
"""provisionner.py — de la source de vérité au serveur en service (M11-E15).

Usage :  uv run outils/provisionner.py <équipement> [--reprendre] [--dry-run]

Cycle de vie (statut NetBox de l'équipement, rôle « serveur-bm ») :

    planned ──► staged (pxe_action=installer) ──► staged (pxe_action=local) ──► active
                   │  allumage, installation,       │  allumage sur le disque,
                   │  arrêt en fin d'installation   │  SSH, accueil Ansible, vérifications
                   └──────────── échec à n'importe quelle étape ──► failed (+ journal NetBox)

Le champ personnalisé « pxe_action » dit au rendu (outils/netbox-provision.py) quel script iPXE
servir pour la MAC : « installer » (gabarit du système) ou « local » (rendre la main au
micrologiciel). Un équipement active est toujours rendu en « local » : il ne se réinstalle jamais.

La machine installée ne rappelle personne : l'orchestrateur observe ce qu'il contrôle déjà
(alimentation par l'API de Proxmox, port SSH, DNS). Aucun secret n'est posé sur la machine.

Identités (jamais en argument de ligne de commande) :
  NetBox  : NETBOX_URL, NETBOX_TOKEN (svc-automatisation : statut, champs et journal des
            équipements « serveur-bm » seulement) ; en CI, variables protégées et masquées.
  Proxmox : fichier PVE_ENV (défaut ~/.config/workbook/pve-provision.env : PVE_API_URL, PVE_NODE,
            PVE_TOKEN_ID, PVE_TOKEN_SECRET, PVE_CACERT), jeton wb-provision@pve!provision
            (rôle WBProvision : VM.Audit, VM.PowerMgmt, VM.GuestAgent.FileRead sur /vms/2112 à
            /vms/2115). La lecture de fichier par l'agent QEMU sert à confirmer la clé d'hôte SSH
            par un canal qui ne passe pas par le réseau (premier contact sans « accept-new »).
Commandes externes (variables d'environnement, valeurs par défaut adaptées au lab) :
  PROVISION_RENDRE   rendu et dépôt des fichiers servis par pxe01 (M11-E06)
  PROVISION_ACCUEIL  accueil Ansible de la machine (clé d'hôte signée, racine, rôle base)
Code de retour : 0 en service (ou déjà en service), 1 échec (équipement « failed »), 2 usage.
"""
from __future__ import annotations

import argparse
import os
import shlex
import socket
import subprocess
import sys
import time
from pathlib import Path

import requests

VMID_AUTORISES = range(2112, 2116)
DOMAINE = "par1.medisphere.internal"
DELAIS = {  # secondes
    "installation": int(os.environ.get("PROVISION_DELAI_INSTALLATION", "3600")),
    "demarrage": int(os.environ.get("PROVISION_DELAI_DEMARRAGE", "600")),
    "arret": 120,
}
RENDRE = os.environ.get("PROVISION_RENDRE", "uv run outils/netbox-provision.py deployer")
ACCUEIL = os.environ.get(
    "PROVISION_ACCUEIL",
    "ansible-playbook playbooks/accueil-bm.yml --limit {nom} -e accueil_known_hosts={known_hosts}",
)
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "provisionner"
ANSIBLE_PROJET = os.environ.get(
    "ANSIBLE_PROJET", str(Path(os.environ.get("WB_SRC", Path.home() / "src")) / "ansible")
)


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
        r = self.s.get(f"{self.url}/dcim/devices/", params={"name": nom}, timeout=15)
        r.raise_for_status()
        res = r.json()["results"]
        if len(res) != 1:
            raise Echec(f"NetBox : {len(res)} équipement(s) nommé(s) {nom}")
        return res[0]

    def modifier(self, dev: dict, **champs) -> None:
        if self.dry_run:
            journal_local(f"[dry-run] NetBox {dev['name']} : {champs}")
            return
        r = self.s.patch(f"{self.url}/dcim/devices/{dev['id']}/", json=champs, timeout=15)
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
                "assigned_object_type": "dcim.device",
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
            raise Echec(f"Proxmox : VM « {nom} » introuvable ou hors de 2112-2115 ({ids})")
        return ids[0]

    def etat(self, vmid: int) -> str:
        r = self.s.get(f"{self.url}/nodes/{self.noeud}/qemu/{vmid}/status/current", timeout=15)
        r.raise_for_status()
        return r.json()["data"]["status"]  # running, stopped

    def lire_fichier(self, vmid: int, chemin: str) -> str:
        """Lit un fichier de l'invité par l'agent QEMU (privilège VM.GuestAgent.FileRead)."""
        r = self.s.get(f"{self.url}/nodes/{self.noeud}/qemu/{vmid}/agent/file-read",
                       params={"file": chemin}, timeout=30)
        r.raise_for_status()
        return r.json()["data"]["content"]

    def action(self, vmid: int, quoi: str) -> None:  # start, stop
        if self.dry_run:
            journal_local(f"[dry-run] Proxmox {vmid} : {quoi}")
            return
        r = self.s.post(f"{self.url}/nodes/{self.noeud}/qemu/{vmid}/status/{quoi}", timeout=30)
        if r.status_code in (401, 403):
            raise Echec(f"Proxmox refuse « {quoi} » sur {vmid} ({r.status_code}) : jeton wb-provision, rôle WBProvision")
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


def lancer(commande: str, quoi: str, cwd: str | None = None, dry_run: bool = False) -> None:
    if dry_run:
        journal_local(f"[dry-run] {quoi} : {commande}")
        return
    r = subprocess.run(shlex.split(commande), cwd=cwd, check=False)
    if r.returncode != 0:
        raise Echec(f"{quoi} : « {commande} » a échoué (code {r.returncode})")


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
    r = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ControlPath=none",
         "-o", "ConnectTimeout=8", f"admin@{nom}.{DOMAINE}", "true"],
        check=False, capture_output=True,
    )
    return r.returncode == 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("equipement")
    p.add_argument("--reprendre", action="store_true", help="reprendre un équipement « failed »")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()

    for v in ("NETBOX_URL", "NETBOX_TOKEN"):
        if not os.environ.get(v):
            print(f"Variable {v} absente", file=sys.stderr)
            return 2
    nb = NetBox(os.environ["NETBOX_URL"], os.environ["NETBOX_TOKEN"], a.dry_run)
    pve_env = Path(os.environ.get("PVE_ENV", Path.home() / ".config/workbook/pve-provision.env"))
    pve = Proxmox(lire_env(pve_env), a.dry_run)

    dev = nb.equipement(a.equipement)
    nom = dev["name"]
    if (dev.get("role") or {}).get("slug") != "serveur-bm":
        print(f"{nom} n'a pas le rôle serveur-bm : refus", file=sys.stderr)
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

    etape = "préparation"
    try:
        vmid = pve.vmid(nom)
        action = (dev.get("custom_fields") or {}).get("pxe_action")
        # Reprise : une machine déjà installée (pxe_action=local) ne repasse pas par l'installation.
        if not (statut in ("staged", "failed") and action == "local"):
            etape = "installation"
            nb.modifier(dev, status="staged", custom_fields={"pxe_action": "installer"})
            nb.journal(dev, "info", f"{etape} : début (statut staged, script iPXE d'installation)")
            lancer(RENDRE, "rendu des fichiers servis", dry_run=a.dry_run)
            if pve.etat(vmid) == "running":
                pve.action(vmid, "stop")
                attendre(lambda: pve.etat(vmid) == "stopped", DELAIS["arret"], 5, "arrêt de la VM")
            pve.action(vmid, "start")
            if not a.dry_run:
                attendre(lambda: pve.etat(vmid) == "stopped", DELAIS["installation"], 30,
                         "fin d'installation (la machine s'éteint) : regarde sa console")
            nb.journal(dev, "info", f"{etape} : terminée (machine éteinte)")

        etape = "premier démarrage"
        nb.modifier(dev, status="staged", custom_fields={"pxe_action": "local"})
        lancer(RENDRE, "rendu des fichiers servis (démarrage local)", dry_run=a.dry_run)
        if pve.etat(vmid) == "stopped":
            pve.action(vmid, "start")
        if not a.dry_run:
            attendre(lambda: port_ouvert(ip, 22), DELAIS["demarrage"], 10,
                     f"SSH de {ip} (si la console montre une réinstallation : rendu « local » non déployé)")
            attendre(lambda: resolu(f"{nom}.{DOMAINE}", ip), 120, 10, f"DNS {nom}.{DOMAINE} → {ip}")
        nb.journal(dev, "info", f"{etape} : SSH ouvert, nom résolu")

        etape = "clé d'hôte"
        CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
        known_hosts = CACHE / f"known_hosts-{nom}"
        if not a.dry_run:
            # Clé publique lue DANS la machine par l'agent QEMU, pas sur le réseau : c'est elle
            # qu'Ansible exigera de sshd (StrictHostKeyChecking=yes) au premier contact.
            attendre(lambda: _essai(lambda: pve.lire_fichier(vmid, "/etc/ssh/ssh_host_ed25519_key.pub")),
                     120, 10, "agent QEMU de la machine (paquet qemu-guest-agent, option agent de la VM)")
            cle = pve.lire_fichier(vmid, "/etc/ssh/ssh_host_ed25519_key.pub").split()
            known_hosts.write_text(f"{nom},{nom}.{DOMAINE},{ip} {cle[0]} {cle[1]}\n", encoding="utf-8")
        nb.journal(dev, "info", f"{etape} : clé ED25519 lue par l'agent QEMU")

        etape = "accueil Ansible"
        lancer(ACCUEIL.format(nom=nom, known_hosts=known_hosts), etape, cwd=ANSIBLE_PROJET, dry_run=a.dry_run)
        if not a.dry_run and not ssh_certificat_ok(nom):
            raise Echec("clé d'hôte non reconnue après l'accueil (certificat d'hôte, @cert-authority)")
        nb.journal(dev, "info", f"{etape} : racine, clé d'hôte signée, rôle base")

        etape = "mise en service"
        nb.modifier(dev, status="active", custom_fields={"pxe_action": "local"})
        lancer(RENDRE, "rendu des fichiers servis (en service)", dry_run=a.dry_run)
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


if __name__ == "__main__":
    sys.exit(main())
