#!/usr/bin/env python3
"""inventaire-redfish.py — inventaire matériel lu sur un contrôleur Redfish, écrit dans NetBox (M11-E18).

Usage : uv run outils/inventaire-redfish.py [--equipement hp01] [--dry-run]

Lecture (Redfish, en suivant les liens @odata.id depuis /redfish/v1/, sans chemin en dur) :
  système   : numéro de série, modèle, version du BIOS, processeurs, mémoire ;
  contrôleur: version du firmware (Managers/<n>.FirmwareVersion) ;
  firmwares : ressource propre à HPE sur iLO 4 (lien trouvé dans la section Oem du système).
Écriture (NetBox), seulement ce que l'outil possède :
  équipement : serial, champs personnalisés firmware_bios, firmware_ilo, inventaire_maj ;
  éléments d'inventaire marqués « discovered » : créés, mis à jour, supprimés s'ils disparaissent ;
  les éléments saisis à la main (discovered=false) ne sont jamais touchés.

Identités (jamais en argument) :
  iLO    : fichier ILO_ENV (défaut ~/.config/workbook/ilo-hp01.env, 600) : ILO_HOST, ILO_USER,
           ILO_PASSWORD et, si le certificat de l'iLO est épinglé (M11-E07), ILO_CACERT ;
           sinon le magasin système (certificat de l'iLO émis par step-ca). Jamais verify=False.
  NetBox : NETBOX_URL, NETBOX_TOKEN (svc-automatisation, droits étendus en M11-E18).
Code de retour : 0 sans écart (ou écarts écrits), 3 écarts trouvés en --dry-run, 1 erreur.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
from pathlib import Path

import requests


def lire_env(fichier: Path) -> dict[str, str]:
    if fichier.stat().st_mode & 0o077:
        raise SystemExit(f"{fichier} doit être en 600")
    v = {}
    for ligne in fichier.read_text(encoding="utf-8").splitlines():
        ligne = ligne.strip()
        if ligne and not ligne.startswith("#") and "=" in ligne:
            k, val = ligne.split("=", 1)
            v[k.strip()] = val.strip().strip('"').strip("'")
    return v


class Redfish:
    def __init__(self, env: dict[str, str]):
        self.base = f"https://{env['ILO_HOST']}"
        self.s = requests.Session()
        self.s.verify = env.get("ILO_CACERT") or True
        # Session Redfish (jeton X-Auth-Token) plutôt que l'authentification basique à chaque appel
        r = self.s.post(f"{self.base}/redfish/v1/SessionService/Sessions/",
                        json={"UserName": env["ILO_USER"], "Password": env["ILO_PASSWORD"]}, timeout=20)
        r.raise_for_status()
        self.session = r.headers.get("Location")
        self.s.headers["X-Auth-Token"] = r.headers["X-Auth-Token"]

    def get(self, chemin: str) -> dict:
        url = chemin if chemin.startswith("https://") else self.base + chemin
        r = self.s.get(url, timeout=20)
        r.raise_for_status()
        return r.json()

    def membres(self, collection: str) -> list[dict]:
        return [self.get(m["@odata.id"]) for m in self.get(collection).get("Members", [])]

    def fermer(self) -> None:
        if self.session:
            try:
                self.s.delete(self.session if self.session.startswith("https://") else self.base + self.session, timeout=10)
            except requests.RequestException:
                pass


def trouver_lien(obj, cle: str) -> str | None:
    """Cherche récursivement un lien {cle: {"@odata.id": …}} (sections Oem, Links, links)."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == cle and isinstance(v, dict) and "@odata.id" in v:
                return v["@odata.id"]
            trouve = trouver_lien(v, cle)
            if trouve:
                return trouve
    elif isinstance(obj, list):
        for v in obj:
            trouve = trouver_lien(v, cle)
            if trouve:
                return trouve
    return None


def lire_inventaire(rf: Redfish) -> dict:
    racine = rf.get("/redfish/v1/")
    systeme = rf.membres(racine["Systems"]["@odata.id"])[0]
    manager = rf.membres(racine["Managers"]["@odata.id"])[0]
    inv = {
        "serie": (systeme.get("SerialNumber") or "").strip(),
        "modele": systeme.get("Model", ""),
        "bios": systeme.get("BiosVersion", ""),
        "ilo": manager.get("FirmwareVersion", ""),
        "composants": [],
        "firmwares": [],
    }
    if "Processors" in systeme:
        for p in rf.membres(systeme["Processors"]["@odata.id"]):
            if (p.get("Status") or {}).get("State") == "Absent":
                continue
            inv["composants"].append({"nom": f"CPU {p.get('Socket') or p.get('Id')}",
                                      "modele": p.get("Model", ""), "serie": p.get("SerialNumber", "")})
    memoire = (systeme.get("Memory") or {}).get("@odata.id") or trouver_lien(systeme, "Memory")
    if memoire:
        for m in rf.membres(memoire):
            etat = (m.get("Status") or {}).get("State") or (m.get("DIMMStatus") or "")
            if etat in ("Absent", "NotPresent"):
                continue
            taille = m.get("CapacityMiB") or m.get("SizeMB") or ""
            inv["composants"].append({"nom": f"DIMM {m.get('DeviceLocator') or m.get('Name') or m.get('Id')}",
                                      "modele": f"{m.get('PartNumber') or m.get('Manufacturer') or ''} {taille} Mio".strip(),
                                      "serie": (m.get("SerialNumber") or "").strip()})
    # iLO 4 : inventaire des firmwares propre à HPE (lien dans Oem du système) ; absent ailleurs.
    lien = trouver_lien(systeme, "FirmwareInventory")
    if lien:
        fw = rf.get(lien)
        for groupe in (fw.get("Current") or {}).values():
            for e in groupe if isinstance(groupe, list) else []:
                inv["firmwares"].append(f"{e.get('Name', '?')} {e.get('VersionString', '?')}")
    return inv


class NetBox:
    def __init__(self, url: str, jeton: str):
        self.url = url.rstrip("/") + "/api"
        self.s = requests.Session()
        self.s.headers.update({"Authorization": f"Bearer {jeton}", "Accept": "application/json"})

    def req(self, methode: str, chemin: str, **kw):
        r = self.s.request(methode, f"{self.url}/{chemin}", timeout=20, **kw)
        r.raise_for_status()
        return r.json() if r.content else None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--equipement", default="hp01")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    ilo_env = lire_env(Path(os.environ.get("ILO_ENV", Path.home() / ".config/workbook/ilo-hp01.env")))
    if not os.environ.get("NETBOX_TOKEN"):
        print("NETBOX_TOKEN absent", file=sys.stderr)
        return 1
    nb = NetBox(os.environ.get("NETBOX_URL", "https://nbx01.par1.medisphere.internal"), os.environ["NETBOX_TOKEN"])

    rf = Redfish(ilo_env)
    try:
        inv = lire_inventaire(rf)
    finally:
        rf.fermer()

    devs = nb.req("GET", "dcim/devices/", params={"name": a.equipement})["results"]
    if len(devs) != 1:
        print(f"NetBox : équipement {a.equipement} introuvable", file=sys.stderr)
        return 1
    dev = devs[0]
    cf = dev.get("custom_fields") or {}
    voulu = {"serial": inv["serie"],
             "custom_fields": {"firmware_bios": inv["bios"], "firmware_ilo": inv["ilo"],
                               "inventaire_maj": dt.date.today().isoformat()}}
    ecarts = []
    if dev.get("serial", "") != inv["serie"]:
        ecarts.append(f"serial : {dev.get('serial')!r} → {inv['serie']!r}")
    for k in ("firmware_bios", "firmware_ilo"):
        if cf.get(k) != voulu["custom_fields"][k]:
            ecarts.append(f"{k} : {cf.get(k)!r} → {voulu['custom_fields'][k]!r}")

    existants = {i["name"]: i for i in nb.req("GET", "dcim/inventory-items/",
                                                params={"device_id": dev["id"], "discovered": "true", "limit": 500})["results"]}
    vus = set()
    for c in inv["composants"]:
        vus.add(c["nom"])
        corps = {"device": dev["id"], "name": c["nom"], "part_id": c["modele"][:50],
                 "serial": c["serie"][:50], "discovered": True,
                 "description": "Inventaire Redfish (outils/inventaire-redfish.py)"}
        ancien = existants.get(c["nom"])
        if ancien is None:
            ecarts.append(f"élément d'inventaire à créer : {c['nom']}")
            if not a.dry_run:
                nb.req("POST", "dcim/inventory-items/", json=corps)
        elif (ancien.get("part_id"), ancien.get("serial")) != (corps["part_id"], corps["serial"]):
            ecarts.append(f"élément d'inventaire à mettre à jour : {c['nom']}")
            if not a.dry_run:
                nb.req("PATCH", f"dcim/inventory-items/{ancien['id']}/", json=corps)
    for nom, ancien in existants.items():
        if nom not in vus:
            ecarts.append(f"élément d'inventaire disparu : {nom}")
            if not a.dry_run:
                nb.req("DELETE", f"dcim/inventory-items/{ancien['id']}/")

    print(f"{a.equipement} : {inv['modele']} série {inv['serie']}, BIOS {inv['bios']}, iLO {inv['ilo']}")
    for f in inv["firmwares"]:
        print(f"  firmware : {f}")
    for e in ecarts:
        print(f"  écart : {e}")
    if a.dry_run:
        return 3 if ecarts else 0
    # Date de passage toujours mise à jour (preuve de fraîcheur), le reste seulement si nécessaire
    nb.req("PATCH", f"dcim/devices/{dev['id']}/", json=voulu)
    print("NetBox à jour.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
