#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["requests>=2.32", "pyyaml>=6.0"]
# ///
"""modeliser.py — décrit MédiSphère dans NetBox à partir de modele-medisphere.yml (M06-E05).

Idempotent : chaque objet est cherché par sa clé naturelle (slug, nom, préfixe, adresse…),
créé s'il manque, corrigé s'il diffère (seuls les champs décrits sont comparés), laissé tel
quel sinon. Un second passage n'affiche que « = » (rien à faire).

Usage (depuis le dossier du script, sur adm01) :
    uv run modeliser.py --dry-run          # montre ce qui serait créé ou modifié
    uv run modeliser.py                    # applique

Accès : URL dans NETBOX_URL (défaut https://nbx01.par1.medisphere.internal), jeton v2 en
écriture dans le fichier NETBOX_TOKEN_FILE (défaut ~/.config/workbook/netbox-moi.token : ton
jeton personnel de M06-E05, contenu « nbt_<clé>.<jeton> » ; après M06-E10, le jeton de
svc-automatisation, netbox-auto.token, ne suffit pas : il n'écrit que VMs, interfaces et
adresses), TLS vérifié avec le magasin système (racine de la PKI du
socle), pas avec le magasin de certifi embarqué par requests.

Codes retour : 0 succès ; 1 erreur d'API ; 2 usage ou configuration.
"""

from __future__ import annotations

import argparse
import ipaddress
import os
import stat
import sys
from pathlib import Path
from typing import Any

import requests
import yaml

MAGASIN_SYSTEME = "/etc/ssl/certs/ca-certificates.crt"


class ErreurNetBox(Exception):
    """Réponse inattendue de l'API (le message contient le détail renvoyé par NetBox)."""


class NetBox:
    """Client minimal de l'API REST : GET filtré, POST, PATCH."""

    def __init__(self, url: str, jeton: str, ca: str | bool, simulation: bool) -> None:
        self.base = url.rstrip("/") + "/api/"
        self.simulation = simulation
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Bearer {jeton}",
                "Accept": "application/json",
                "Content-Type": "application/json",
            }
        )
        self.session.verify = ca
        self.compteurs = {"crees": 0, "modifies": 0, "inchanges": 0}
        self._faux_id = 0

    def _appel(self, methode: str, chemin: str, **kwargs: Any) -> Any:
        rep = self.session.request(methode, self.base + chemin, timeout=30, **kwargs)
        if rep.status_code >= 400:
            raise ErreurNetBox(f"{methode} {chemin} -> HTTP {rep.status_code} : {rep.text[:500]}")
        return rep.json() if rep.content else None

    def chercher(self, chemin: str, filtres: dict[str, Any]) -> dict | None:
        if any(isinstance(v, int) and v < 0 for v in filtres.values()):
            return None  # simulation : le parent n'existe pas encore, l'enfant non plus
        res = self._appel("GET", chemin, params={**filtres, "limit": 2})
        if res["count"] > 1:
            raise ErreurNetBox(f"{chemin} {filtres} : {res['count']} objets, clé non unique")
        return res["results"][0] if res["count"] == 1 else None

    def assurer(
        self, chemin: str, cle: dict[str, Any], voulu: dict[str, Any], libelle: str
    ) -> dict:
        """Crée ou met à jour l'objet ; renvoie l'objet (factice en simulation de création)."""
        actuel = self.chercher(chemin, cle)
        if actuel is None:
            print(f"  + {chemin.rstrip('/')} {libelle}")
            self.compteurs["crees"] += 1
            if self.simulation:
                self._faux_id -= 1
                return {"id": self._faux_id, **voulu}
            return self._appel("POST", chemin, json=voulu)
        ecarts = {k: v for k, v in voulu.items() if not egal(k, actuel.get(k), v)}
        if not ecarts:
            print(f"  = {chemin.rstrip('/')} {libelle}")
            self.compteurs["inchanges"] += 1
            return actuel
        print(f"  ~ {chemin.rstrip('/')} {libelle} : {', '.join(sorted(ecarts))}")
        self.compteurs["modifies"] += 1
        if self.simulation:
            return actuel
        return self._appel("PATCH", f"{chemin}{actuel['id']}/", json=ecarts)


def normaliser(valeur: Any) -> Any:
    """Ramène une valeur LUE dans l'API à la forme qu'on ÉCRIT (id, valeur de choix…)."""
    if isinstance(valeur, dict):
        if "value" in valeur and "label" in valeur:  # champ à choix : {"value": "active", …}
            return valeur["value"]
        if "id" in valeur:  # objet lié imbriqué
            return valeur["id"]
        return {k: normaliser(v) for k, v in valeur.items()}
    if isinstance(valeur, list):
        return [normaliser(v) for v in valeur]
    return valeur


def egal(champ: str, lu: Any, voulu: Any) -> bool:
    """La valeur lue correspond-elle à la valeur voulue (au sens de NetBox) ?"""
    if champ == "tags":  # écrites [{"slug": …}], lues comme objets complets : on compare les slugs
        return sorted(e["slug"] for e in lu or []) == sorted(e["slug"] for e in voulu)
    lu = normaliser(lu)
    if isinstance(voulu, dict) and isinstance(lu, dict):
        # custom_fields : on ne compare que les champs décrits
        return all(egal(k, lu.get(k), v) for k, v in voulu.items())
    if isinstance(voulu, list):
        return sorted(map(str, lu or [])) == sorted(map(str, voulu))
    if isinstance(voulu, str) and isinstance(lu, str) and "/" in voulu:
        try:  # préfixes et adresses : 10.10.20.0/24 == 10.10.20.0/24 quelle que soit l'écriture
            return ipaddress.ip_interface(lu) == ipaddress.ip_interface(voulu)
        except ValueError:
            pass
    return lu == voulu


def lire_jeton(chemin: Path) -> str:
    if not chemin.is_file():
        raise SystemExit(f"modeliser : jeton introuvable : {chemin}")
    if stat.S_IMODE(chemin.stat().st_mode) & 0o077:
        raise SystemExit(f"modeliser : {chemin} est lisible par d'autres que toi (chmod 600)")
    jeton = chemin.read_text(encoding="utf-8").strip()
    if not jeton.startswith("nbt_") or "." not in jeton:
        raise SystemExit("modeliser : le jeton doit être un jeton v2 « nbt_<clé>.<jeton> »")
    return jeton


def modeliser(nb: NetBox, m: dict) -> None:
    ids: dict[str, dict[str, int]] = {}

    def garder(espace: str, cle: str, obj: dict) -> None:
        ids.setdefault(espace, {})[cle] = obj["id"]

    print("Organisation")
    r = m["region"]
    garder("region", r["slug"], nb.assurer("dcim/regions/", {"slug": r["slug"]}, r, r["name"]))
    t = m["tenant"]
    garder("tenant", t["slug"], nb.assurer("tenancy/tenants/", {"slug": t["slug"]}, t, t["name"]))
    for s in m["sites"]:
        voulu = {
            **s,
            "status": "active",
            "region": ids["region"][r["slug"]],
            "tenant": ids["tenant"][t["slug"]],
        }
        garder("site", s["slug"], nb.assurer("dcim/sites/", {"slug": s["slug"]}, voulu, s["name"]))
    for e in m["etiquettes"]:
        nb.assurer("extras/tags/", {"slug": e["slug"]}, e, e["name"])

    print("Champ personnalisé vmid")
    nb.assurer(
        "extras/custom-fields/",
        {"name": "vmid"},
        {
            "name": "vmid",
            "label": "VMID",
            "type": "integer",
            "object_types": ["virtualization.virtualmachine"],
            "description": "Identifiant de la VM dans Proxmox VE",
            "required": False,
            "validation_minimum": 100,
            "validation_maximum": 999999999,
        },
        "vmid",
    )

    print("Équipements physiques et cluster")
    for b in m["racks"]:
        voulu = {
            "name": b["name"],
            "site": ids["site"][b["site"]],
            "status": "active",
            "tenant": ids["tenant"][t["slug"]],
            "description": b.get("description", ""),
        }
        garder(
            "rack",
            b["name"],
            nb.assurer(
                "dcim/racks/", {"name": b["name"], "site_id": voulu["site"]}, voulu, b["name"]
            ),
        )
    for f in m["fabricants"]:
        garder(
            "fabricant",
            f["slug"],
            nb.assurer("dcim/manufacturers/", {"slug": f["slug"]}, f, f["name"]),
        )
    for ty in m["types_equipement"]:
        voulu = {
            "model": ty["model"],
            "slug": ty["slug"],
            "manufacturer": ids["fabricant"][ty["fabricant"]],
            "u_height": ty["u_height"],
        }
        garder(
            "type",
            ty["slug"],
            nb.assurer("dcim/device-types/", {"slug": ty["slug"]}, voulu, ty["model"]),
        )
    for ro in m["roles_equipement"]:
        garder(
            "role_eq",
            ro["slug"],
            nb.assurer("dcim/device-roles/", {"slug": ro["slug"]}, ro, ro["name"]),
        )
    for tc in m["types_cluster"]:
        garder(
            "type_cluster",
            tc["slug"],
            nb.assurer("virtualization/cluster-types/", {"slug": tc["slug"]}, tc, tc["name"]),
        )
    for c in m["clusters"]:
        voulu = {
            "name": c["name"],
            "type": ids["type_cluster"][c["type"]],
            "status": "active",
            "scope_type": "dcim.site",
            "scope_id": ids["site"][c["site"]],
            "tenant": ids["tenant"][t["slug"]],
            "description": c.get("description", ""),
        }
        garder(
            "cluster",
            c["name"],
            nb.assurer("virtualization/clusters/", {"name": c["name"]}, voulu, c["name"]),
        )
    for d in m["equipements"]:
        voulu = {
            "name": d["name"],
            "device_type": ids["type"][d["type"]],
            "role": ids["role_eq"][d["role"]],
            "site": ids["site"][d["site"]],
            "rack": ids["rack"][d["rack"]],
            "position": d["position"],
            "face": "front",
            "status": "active",
            "tenant": ids["tenant"][t["slug"]],
            "description": d.get("description", ""),
        }
        if "cluster" in d:
            voulu["cluster"] = ids["cluster"][d["cluster"]]
        nb.assurer("dcim/devices/", {"name": d["name"]}, voulu, d["name"])

    print("Adressage : VLAN, préfixes, plages")
    for ri in m["roles_ipam"]:
        garder(
            "role_ipam", ri["slug"], nb.assurer("ipam/roles/", {"slug": ri["slug"]}, ri, ri["name"])
        )
    g = m["groupe_vlan"]
    groupe = nb.assurer(
        "ipam/vlan-groups/",
        {"slug": g["slug"]},
        {
            "name": g["name"],
            "slug": g["slug"],
            "scope_type": "dcim.site",
            "scope_id": ids["site"][g["site"]],
        },
        g["name"],
    )
    for v in m["vlans"]:
        voulu = {
            "vid": v["vid"],
            "name": v["name"],
            "group": groupe["id"],
            "status": "active",
            "tenant": ids["tenant"][t["slug"]],
            "description": v["description"],
        }
        vlan = nb.assurer(
            "ipam/vlans/",
            {"vid": v["vid"], "group_id": groupe["id"]},
            voulu,
            f"{v['vid']} {v['name']}",
        )
        reseau = ipaddress.ip_network(f"10.10.{v['vid']}.0/24")
        nb.assurer(
            "ipam/prefixes/",
            {"prefix": str(reseau), "vrf_id": "null"},
            {
                "prefix": str(reseau),
                "status": "active",
                "vlan": vlan["id"],
                "scope_type": "dcim.site",
                "scope_id": ids["site"]["par1"],
                "tenant": ids["tenant"][t["slug"]],
                "description": f"VLAN {v['vid']} {v['name']}",
            },
            str(reseau),
        )
        for p in m["convention_plages"]:
            debut, fin = reseau[p["debut"]], reseau[p["fin"]]
            nb.assurer(
                "ipam/ip-ranges/",
                {"start_address": f"{debut}/24", "vrf_id": "null"},
                {
                    "start_address": f"{debut}/24",
                    "end_address": f"{fin}/24",
                    "status": "active",
                    "role": ids["role_ipam"][p["role"]],
                    "tenant": ids["tenant"][t["slug"]],
                    "description": f"{p['description']} (VLAN {v['vid']})",
                },
                f"{debut}-{fin}",
            )
    for p in m["prefixes"]:
        voulu = {
            "prefix": p["prefix"],
            "status": p["status"],
            "tenant": ids["tenant"][t["slug"]],
            "description": p["description"],
        }
        if "site" in p:
            voulu |= {"scope_type": "dcim.site", "scope_id": ids["site"][p["site"]]}
        nb.assurer("ipam/prefixes/", {"prefix": p["prefix"], "vrf_id": "null"}, voulu, p["prefix"])

    print("Machines virtuelles du socle")
    for vm in m["vms"]:
        voulu = {
            "name": vm["name"],
            "status": "active",
            "site": ids["site"]["par1"],
            "cluster": ids["cluster"]["pve01"],
            "tenant": ids["tenant"][t["slug"]],
            "vcpus": vm["vcpus"],
            "memory": vm["memory"],
            "disk": vm["disk"],
            "tags": [{"slug": s} for s in vm["tags"]],
            "custom_fields": {"vmid": vm["vmid"]},
        }
        objet = nb.assurer(
            "virtualization/virtual-machines/", {"name": vm["name"]}, voulu, vm["name"]
        )
        primaire = None
        for itf in vm["interfaces"]:
            interface = nb.assurer(
                "virtualization/interfaces/",
                {"virtual_machine_id": objet["id"], "name": itf["name"]},
                {"virtual_machine": objet["id"], "name": itf["name"], "enabled": True},
                f"{vm['name']}/{itf['name']}",
            )
            for adresse in itf["ips"]:
                ip = nb.assurer(
                    "ipam/ip-addresses/",
                    {"address": adresse, "vrf_id": "null"},
                    {
                        "address": adresse,
                        "status": "active",
                        "dns_name": f"{vm['name']}.par1.medisphere.internal",
                        "assigned_object_type": "virtualization.vminterface",
                        "assigned_object_id": interface["id"],
                        "tenant": ids["tenant"][t["slug"]],
                    },
                    f"{adresse} ({vm['name']})",
                )
                if itf.get("primaire") and primaire is None:
                    primaire = ip
        if primaire is not None:
            # L'IP primaire ne peut être posée qu'une fois l'adresse rattachée à une interface
            # de la VM : d'où ce second passage sur la VM.
            nb.assurer(
                "virtualization/virtual-machines/",
                {"name": vm["name"]},
                {"primary_ip4": primaire["id"]},
                f"{vm['name']} (IP primaire)",
            )


def main() -> int:
    parser = argparse.ArgumentParser(description="Décrit MédiSphère dans NetBox (idempotent).")
    parser.add_argument(
        "--modele", type=Path, default=Path(__file__).with_name("modele-medisphere.yml")
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="ne rien écrire, montrer les différences"
    )
    parser.add_argument(
        "--ca",
        default=os.environ.get("NETBOX_CA", MAGASIN_SYSTEME),
        help="magasin de confiance TLS",
    )
    args = parser.parse_args()

    url = os.environ.get("NETBOX_URL", "https://nbx01.par1.medisphere.internal")
    jeton = lire_jeton(
        Path(
            os.environ.get("NETBOX_TOKEN_FILE", "~/.config/workbook/netbox-moi.token")
        ).expanduser()
    )
    try:
        modele = yaml.safe_load(args.modele.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as e:
        print(f"modeliser : modèle illisible : {e}", file=sys.stderr)
        return 2

    nb = NetBox(url, jeton, args.ca, args.dry_run)
    try:
        modeliser(nb, modele)
    except (ErreurNetBox, requests.RequestException) as e:
        print(f"modeliser : {e}", file=sys.stderr)
        return 1
    c = nb.compteurs
    mode = " (simulation : rien n'a été écrit)" if args.dry_run else ""
    print(
        f"\nBilan{mode} : {c['crees']} créé(s), {c['modifies']} modifié(s), {c['inchanges']} inchangé(s)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
