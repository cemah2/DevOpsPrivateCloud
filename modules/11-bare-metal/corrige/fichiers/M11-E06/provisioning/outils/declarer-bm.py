#!/usr/bin/env python3
"""declarer-bm.py — « réceptionner » les serveurs nus du lab dans NetBox (M11-E06).

Idempotent : crée ce qui manque, corrige les champs DÉCRITS par donnees/bm.yml, ne touche à rien
d'autre. Le STATUT n'est posé qu'à la création (« planned ») : ensuite il appartient à la chaîne
(et aux humains), jamais à ce script.

    uv run outils/declarer-bm.py [--simulation]

Écriture avec TON jeton personnel (~/.config/workbook/netbox-moi.token, une ligne nbt_…) :
svc-automatisation n'a pas, et ne doit pas avoir, le droit d'écrire les équipements.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import requests
import yaml

RACINE = Path(__file__).resolve().parent.parent
MAGASIN_SYSTEME = "/etc/ssl/certs/ca-certificates.crt"


class NetBox:
    def __init__(self, url: str, jeton: str, simulation: bool) -> None:
        self.url = url.rstrip("/") + "/api/"
        self.s = requests.Session()
        self.s.headers.update({"Authorization": f"Bearer {jeton}", "Accept": "application/json"})
        self.s.verify = MAGASIN_SYSTEME
        self.simulation = simulation

    def _req(self, methode: str, chemin: str, **kw) -> dict:
        rep = self.s.request(methode, self.url + chemin, timeout=15, **kw)
        if rep.status_code >= 400:
            sys.exit(f"declarer-bm : {methode} {chemin} → {rep.status_code} {rep.text[:300]}")
        return rep.json() if rep.content else {}

    def chercher(self, chemin: str, **filtres) -> dict | None:
        res = self._req("GET", chemin, params=filtres)["results"]
        return res[0] if res else None

    def assurer(self, chemin: str, filtres: dict, voulu: dict, creation: dict | None = None) -> dict:
        """Crée (voulu + creation) si absent ; sinon PATCH des seuls champs de « voulu » qui diffèrent."""
        obj = self.chercher(chemin, **filtres)
        if obj is None:
            print(f"+ {chemin} {filtres}")
            if self.simulation:
                return {"id": 0}
            return self._req("POST", chemin, json={**voulu, **(creation or {})})
        ecarts = {k: v for k, v in voulu.items() if normaliser(obj.get(k)) != normaliser(v)}
        if ecarts:
            print(f"~ {chemin} {filtres} : {', '.join(sorted(ecarts))}")
            if not self.simulation:
                obj = self._req("PATCH", f"{chemin}{obj['id']}/", json=ecarts)
        else:
            print(f"= {chemin} {filtres}")
        return obj


def normaliser(v):
    """Lecture NetBox → forme d'écriture : objet lié → id, choix → value, étiquettes → slugs."""
    if isinstance(v, dict):
        return v.get("id", v.get("value"))
    if isinstance(v, list):
        return sorted((x.get("slug") if isinstance(x, dict) else x) for x in v)
    return v


def principal() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--simulation", action="store_true")
    ap.add_argument("--donnees", type=Path, default=RACINE / "donnees" / "bm.yml")
    ap.add_argument("--netbox-url", default="https://nbx01.par1.medisphere.internal")
    ap.add_argument("--jeton", type=Path, default=Path.home() / ".config/workbook/netbox-moi.token")
    a = ap.parse_args()
    d = yaml.safe_load(a.donnees.read_text(encoding="utf-8"))
    nb = NetBox(a.netbox_url, a.jeton.read_text(encoding="utf-8").strip(), a.simulation)

    site = nb.chercher("dcim/sites/", slug=d["site"])
    fabricant = nb.chercher("dcim/manufacturers/", slug=d["fabricant"])
    if not site or not fabricant:
        sys.exit("declarer-bm : site ou fabricant absent (modélisation de M06-E05)")
    for e in d["etiquettes"]:
        nb.assurer("extras/tags/", {"slug": e["slug"]}, {"name": e["name"], "color": e["color"]}, {"slug": e["slug"]})
    r = d["role"]
    role = nb.assurer(
        "dcim/device-roles/", {"slug": r["slug"]}, {"name": r["name"], "color": r["color"]}, {"slug": r["slug"]}
    )
    t = d["type"]
    dtype = nb.assurer(
        "dcim/device-types/",
        {"slug": t["slug"]},
        {"model": t["model"], "manufacturer": fabricant["id"], "u_height": t["u_height"], "comments": t["comments"]},
        {"slug": t["slug"]},
    )
    plateformes = {
        p["slug"]: nb.assurer("dcim/platforms/", {"slug": p["slug"]}, {"name": p["name"]}, {"slug": p["slug"]})
        for p in d["plateformes"]
    }

    for s in d["serveurs"]:
        dev = nb.assurer(
            "dcim/devices/",
            {"name": s["nom"], "site_id": site["id"]},
            {
                "role": role["id"],
                "device_type": dtype["id"],
                "platform": plateformes[s["plateforme"]]["id"],
                "serial": s["serie"],
                "tags": [{"slug": "env-m11"}],
            },
            {"name": s["nom"], "site": site["id"], "status": "planned"},  # statut : à la création SEULEMENT
        )
        if a.simulation and dev["id"] == 0:
            continue
        iface = nb.assurer(
            "dcim/interfaces/",
            {"device_id": dev["id"], "name": "eno1"},
            {"type": "1000base-t"},
            {"device": dev["id"], "name": "eno1"},
        )
        # NetBox ≥ 4.2 : la MAC est un objet rattaché à l'interface, puis désignée comme primaire.
        mac = nb.assurer(
            "dcim/mac-addresses/",
            {"mac_address": s["mac"]},
            {"assigned_object_type": "dcim.interface", "assigned_object_id": iface["id"]},
            {"mac_address": s["mac"]},
        )
        nb.assurer("dcim/interfaces/", {"device_id": dev["id"], "name": "eno1"}, {"primary_mac_address": mac["id"]})
        ip = nb.assurer(
            "ipam/ip-addresses/",
            {"address": s["ip"]},
            {
                "status": "active",
                "dns_name": f"{s['nom']}.par1.medisphere.internal",
                "assigned_object_type": "dcim.interface",
                "assigned_object_id": iface["id"],
            },
            {"address": s["ip"]},
        )
        nb.assurer("dcim/devices/", {"name": s["nom"], "site_id": site["id"]}, {"primary_ip4": ip["id"]})
    print("Simulation : rien n'a été écrit." if a.simulation else "NetBox à jour.")
    return 0


if __name__ == "__main__":
    sys.exit(principal())
