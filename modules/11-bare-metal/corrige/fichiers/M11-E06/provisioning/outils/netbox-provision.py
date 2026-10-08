#!/usr/bin/env python3
"""netbox-provision.py — la chaîne de provisioning générée depuis NetBox (M11-E06).

Lit les équipements du rôle « serveur-bm » (site par1) dans NetBox, CONTRÔLE leurs données, puis
rend, avec les gabarits de gabarits/ :
  rendu/http/ipxe/mac-<mac-avec-tirets>.ipxe   un script par machine valide (installer si « planned »,
                                               disque local sinon) ;
  rendu/http/kickstart/<nom>.ks                un kickstart par machine Rocky « planned » ;
  rendu/kea_reservations_prov.yml              les réservations du sous-réseau 60 (fichier de
                                               variables pour plateforme/ansible) ;
et, avec --kea-ansible, copie ce dernier fichier dans la copie de travail de plateforme/ansible.

    uv run outils/netbox-provision.py rendre \
        [--kea-ansible ~/src/ansible/inventories/lab/group_vars/role_dns/kea_reservations_prov.yml]
    uv run outils/netbox-provision.py rendre --depuis-json tests/donnees/netbox.json   (sans réseau)

Lecture seule dans NetBox : jeton de lecture de svc-automatisation (fichier netbox-ansible.env,
variable NETBOX_TOKEN), lu sans exécuter le fichier. TLS vérifié avec le magasin du système.
Code de sortie : 0 si tout est rendu, 1 si une machine « planned » est refusée, 2 en cas d'erreur
d'accès ou de configuration. Le jeton n'apparaît ni dans la sortie ni dans les fichiers rendus.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import urlsplit

import jinja2
import requests
import yaml

RACINE = Path(__file__).resolve().parent.parent
PLATEFORMES = {"debian-13", "rocky-10"}
NOM_VALIDE = re.compile(r"^bm[0-9]{2}$")
MAC_VALIDE = re.compile(r"^([0-9a-f]{2}:){5}[0-9a-f]{2}$")
MAGASIN_SYSTEME = "/etc/ssl/certs/ca-certificates.crt"


class ErreurAcces(Exception):
    """NetBox injoignable, jeton absent ou refusé : rien n'est rendu."""


@dataclass(frozen=True)
class Machine:
    nom: str
    statut: str
    plateforme: str
    mac: str
    ip: str  # avec le masque, telle que NetBox la stocke (10.10.60.101/24)
    dns_name: str

    @property
    def ip_seule(self) -> str:
        return self.ip.split("/")[0]

    @property
    def mac_tirets(self) -> str:
        # Forme de ${netX/mac:hexhyp} dans iPXE : minuscules, tirets.
        return self.mac.replace(":", "-")

    @property
    def fqdn(self) -> str:
        return self.dns_name


@dataclass
class Bilan:
    valides: list[Machine] = field(default_factory=list)
    refus: list[tuple[str, str, str]] = field(default_factory=list)  # (nom, statut, motif)

    @property
    def refus_bloquants(self) -> list[tuple[str, str, str]]:
        return [r for r in self.refus if r[1] == "planned"]


# --- Lecture ---------------------------------------------------------------------------------------


def lire_env(chemin: Path, cle: str) -> str:
    """Valeur de CLE dans un fichier KEY=valeur (guillemets facultatifs), sans l'exécuter."""
    try:
        lignes = chemin.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ErreurAcces(f"fichier illisible : {chemin} ({exc.strerror})") from None
    motif = re.compile(rf"^\s*(?:export\s+)?{re.escape(cle)}=(['\"]?)(.*)\1\s*$")
    for ligne in lignes:
        trouve = motif.match(ligne)
        if trouve and trouve.group(2):
            return trouve.group(2)
    raise ErreurAcces(f"{cle} absent de {chemin}")


class NetBox:
    """Client minimal de l'API REST de NetBox 4.6, en lecture."""

    def __init__(self, url: str, jeton: str, ca: str, delai: float = 15.0) -> None:
        self.url = url.rstrip("/")
        self.hote = urlsplit(self.url).netloc
        self.session = requests.Session()
        self.session.headers.update({"Authorization": f"Bearer {jeton}", "Accept": "application/json"})
        self.ca = ca
        self.delai = delai

    def _get(self, url: str, params: dict | None = None) -> dict:
        try:
            rep = self.session.get(url, params=params, verify=self.ca, timeout=self.delai)
        except requests.RequestException as exc:
            # Le message de requests ne contient jamais l'en-tête Authorization.
            raise ErreurAcces(f"NetBox injoignable : {exc.__class__.__name__}") from None
        if rep.status_code in (401, 403):
            raise ErreurAcces(f"NetBox refuse l'accès ({rep.status_code}) à {urlsplit(url).path} : droits du jeton ?")
        if rep.status_code != 200:
            raise ErreurAcces(f"NetBox répond {rep.status_code} sur {urlsplit(url).path}")
        return rep.json()

    def liste(self, chemin: str, params: dict) -> list[dict]:
        """Tous les résultats d'une liste paginée. Ne suit « next » que vers le même hôte."""
        resultats: list[dict] = []
        url: str | None = f"{self.url}/api/{chemin}"
        p: dict | None = {**params, "limit": 200}
        while url:
            if urlsplit(url).netloc != self.hote:
                raise ErreurAcces("lien de pagination vers un autre hôte : refusé")
            page = self._get(url, p)
            resultats.extend(page.get("results", []))
            url, p = page.get("next"), None
        return resultats

    def objet(self, chemin: str) -> dict:
        return self._get(f"{self.url}/api/{chemin}")


def lire_netbox(nb: NetBox, role: str = "serveur-bm", site: str = "par1") -> list[dict]:
    """Équipements du rôle, sous forme de dictionnaires « bruts normalisés » (pas encore contrôlés)."""
    machines = []
    for d in nb.liste("dcim/devices/", {"role": role, "site": site}):
        interfaces = nb.liste("dcim/interfaces/", {"device_id": d["id"], "name": "eno1"})
        mac = ""
        if interfaces:
            i = interfaces[0]
            # NetBox ≥ 4.2 : la MAC est un objet ; « mac_address » de l'interface la reflète en lecture.
            primaire = i.get("primary_mac_address") or {}
            mac = primaire.get("mac_address") or i.get("mac_address") or ""
        ip, dns_name = "", ""
        if d.get("primary_ip4"):
            ip = d["primary_ip4"].get("address", "")
            dns_name = nb.objet(f"ipam/ip-addresses/{d['primary_ip4']['id']}/").get("dns_name", "")
        machines.append(
            {
                "nom": d.get("name") or "",
                "statut": (d.get("status") or {}).get("value", ""),
                "plateforme": (d.get("platform") or {}).get("slug", ""),
                "mac": mac,
                "ip": ip,
                "dns_name": dns_name,
            }
        )
    return machines


# --- Contrôle ---------------------------------------------------------------------------------------


def controler(brutes: list[dict], parametres: dict) -> Bilan:
    """Sépare les machines utilisables des refus. Fonction pure : testée sans réseau."""
    reseau = ipaddress.ip_network(parametres["reseau"])
    debut = ipaddress.ip_address(parametres["plage_debut"])
    fin = ipaddress.ip_address(parametres["plage_fin"])
    domaine = parametres["domaine"]
    bilan = Bilan()

    macs = [str(b.get("mac", "")).lower() for b in brutes]
    ips = [str(b.get("ip", "")).split("/")[0] for b in brutes]

    for b in sorted(brutes, key=lambda x: x.get("nom", "")):
        nom, statut = b.get("nom", ""), b.get("statut", "")
        mac = str(b.get("mac", "")).lower()
        ip = str(b.get("ip", ""))
        motifs = []
        if not NOM_VALIDE.match(nom):
            motifs.append(f"nom « {nom} » hors convention (bmNN)")
        if not MAC_VALIDE.match(mac):
            motifs.append("adresse MAC absente ou invalide sur eno1")
        elif macs.count(mac) > 1:
            motifs.append(f"MAC {mac} en double dans NetBox")
        if b.get("plateforme") not in PLATEFORMES:
            motifs.append(f"plate-forme « {b.get('plateforme') or 'aucune'} » inconnue de la chaîne")
        try:
            iface = ipaddress.ip_interface(ip)
            adresse = iface.ip
            if iface.network != reseau:
                motifs.append(f"IP primaire {ip} hors de {reseau}")
            elif not debut <= adresse <= fin:
                motifs.append(f"IP primaire {adresse} hors de la plage {debut}-{fin}")
            elif ips.count(str(adresse)) > 1:
                motifs.append(f"IP {adresse} en double dans NetBox")
        except ValueError:
            motifs.append("IP primaire absente")
        if b.get("dns_name") != f"{nom}.{domaine}":
            motifs.append(f"dns_name « {b.get('dns_name') or 'vide'} » ≠ {nom}.{domaine}")

        if motifs:
            bilan.refus.append((nom or "?", statut, " ; ".join(motifs)))
        else:
            bilan.valides.append(Machine(nom, statut, b["plateforme"], mac, ip, b["dns_name"]))
    return bilan


# --- Rendu ------------------------------------------------------------------------------------------


def environnement(gabarits: Path) -> jinja2.Environment:
    return jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(gabarits)),
        undefined=jinja2.StrictUndefined,  # une variable manquante est une erreur, pas une chaîne vide
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
        autoescape=False,  # noqa: S701 — scripts iPXE, kickstart et YAML : pas de HTML à échapper
    )


def rendre(bilan: Bilan, parametres: dict, gabarits: Path, sortie: Path) -> list[Path]:
    """Rend tous les fichiers dans un dossier NEUF (rien d'une exécution précédente ne survit)."""
    env = environnement(gabarits)
    if sortie.exists():
        shutil.rmtree(sortie)
    (sortie / "http" / "ipxe").mkdir(parents=True)
    (sortie / "http" / "kickstart").mkdir(parents=True)
    ecrits = []

    for m in bilan.valides:  # déjà triées par nom : rendu déterministe
        f = sortie / "http" / "ipxe" / f"mac-{m.mac_tirets}.ipxe"
        f.write_text(env.get_template("ipxe-hote.ipxe.j2").render(m=m, p=parametres), encoding="utf-8")
        ecrits.append(f)
        if m.statut == "planned" and m.plateforme == "rocky-10":
            f = sortie / "http" / "kickstart" / f"{m.nom}.ks"
            f.write_text(env.get_template("rocky10.ks.j2").render(m=m, p=parametres), encoding="utf-8")
            ecrits.append(f)

    f = sortie / "kea_reservations_prov.yml"
    f.write_text(env.get_template("kea-reservations.yml.j2").render(machines=bilan.valides), encoding="utf-8")
    yaml.safe_load(f.read_text(encoding="utf-8"))  # le fichier rendu doit rester du YAML valide
    ecrits.append(f)
    return ecrits


# --- Interface en ligne de commande -----------------------------------------------------------------


def principal(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Rend la chaîne de provisioning depuis NetBox (M11-E06).")
    sous = ap.add_subparsers(dest="commande", required=True)
    r = sous.add_parser("rendre", help="lire NetBox, contrôler, rendre")
    r.add_argument("--netbox-url", default=os.environ.get("NETBOX_URL", "https://nbx01.par1.medisphere.internal"))
    r.add_argument(
        "--jeton-env",
        type=Path,
        default=Path(os.environ.get("NETBOX_ENV_FILE", Path.home() / ".config/workbook/netbox-ansible.env")),
        help="fichier qui contient NETBOX_TOKEN (lu, jamais exécuté)",
    )
    r.add_argument("--ca", default=MAGASIN_SYSTEME, help="magasin de certificats pour vérifier NetBox")
    r.add_argument("--depuis-json", type=Path, help="données au format de lire_netbox() au lieu de NetBox (tests, CI)")
    r.add_argument("--parametres", type=Path, default=RACINE / "parametres.yml")
    r.add_argument("--gabarits", type=Path, default=RACINE / "gabarits")
    r.add_argument("--sortie", type=Path, default=RACINE / "rendu")
    r.add_argument(
        "--kea-ansible", type=Path, help="copier les réservations dans la copie de travail de plateforme/ansible"
    )
    a = ap.parse_args(argv)

    try:
        parametres = yaml.safe_load(a.parametres.read_text(encoding="utf-8"))
        if a.depuis_json:
            brutes = json.loads(a.depuis_json.read_text(encoding="utf-8"))
        else:
            jeton = lire_env(a.jeton_env, "NETBOX_TOKEN")
            brutes = lire_netbox(NetBox(a.netbox_url, jeton, a.ca))
    except (ErreurAcces, OSError, ValueError, yaml.YAMLError) as exc:
        print(f"netbox-provision : {exc}", file=sys.stderr)
        return 2

    bilan = controler(brutes, parametres)
    try:
        ecrits = rendre(bilan, parametres, a.gabarits, a.sortie)
    except jinja2.TemplateError as exc:
        print(f"netbox-provision : gabarit en erreur : {exc}", file=sys.stderr)
        return 2
    if a.kea_ansible:
        shutil.copyfile(a.sortie / "kea_reservations_prov.yml", a.kea_ansible)

    for m in bilan.valides:
        action = "installation" if m.statut == "planned" else "disque local"
        print(f"[rendu]  {m.nom:6} {m.statut:10} {m.plateforme:10} {m.mac} {m.ip_seule:15} → {action}")
    for nom, statut, motif in bilan.refus:
        print(f"[refus]  {nom:6} {statut:10} {motif}")
    print(
        f"Bilan : {len(bilan.valides)} machine(s) rendue(s), {len(bilan.refus)} refusée(s), "
        f"{len(ecrits)} fichier(s) dans {a.sortie}."
    )
    if bilan.refus_bloquants:
        print("Au moins une machine « planned » est refusée : corrige NetBox avant de publier.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(principal())
