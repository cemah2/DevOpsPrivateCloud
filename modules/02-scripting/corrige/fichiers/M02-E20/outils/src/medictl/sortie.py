"""Mise en forme des sorties de medictl (M02-E15).

Contrat de la sortie JSON de « vm list » (relue par d'autres outils, à ne pas
casser sans version majeure) : une liste d'objets
  {vmid, name, status, node, pool, template, cpus, memory_mib, disk_gib, tags}
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from typing import Any

MIO = 1024**2
GIO = 1024**3


def etiquettes(ressource: dict) -> list[str]:
    """Proxmox renvoie les étiquettes en une chaîne séparée par « ; »."""
    return sorted(t for t in str(ressource.get("tags") or "").split(";") if t)


def resume_vm(r: dict) -> dict[str, Any]:
    return {
        "vmid": r["vmid"],
        "name": r.get("name", ""),
        "status": r.get("status", "inconnu"),
        "node": r.get("node", ""),
        "pool": r.get("pool"),
        "template": str(r.get("template", 0)) == "1",
        "cpus": int(r.get("maxcpu", 0)),
        "memory_mib": int(r.get("maxmem", 0)) // MIO,
        "disk_gib": round(int(r.get("maxdisk", 0)) / GIO, 1),
        "tags": etiquettes(r),
    }


def en_json(donnees: Any) -> str:
    return json.dumps(donnees, ensure_ascii=False, indent=2)


def en_tableau(lignes: Sequence[dict[str, Any]], colonnes: Sequence[tuple[str, str]]) -> str:
    """Tableau texte aligné. colonnes : (clé, en-tête)."""

    def texte(valeur: Any) -> str:
        if isinstance(valeur, list):
            return ",".join(map(str, valeur)) or "-"
        if isinstance(valeur, bool):
            return "oui" if valeur else "non"
        return "-" if valeur in (None, "") else str(valeur)

    cellules = [[texte(ligne.get(cle)) for cle, _ in colonnes] for ligne in lignes]
    largeurs = [
        max([len(entete)] + [len(c[i]) for c in cellules]) for i, (_, entete) in enumerate(colonnes)
    ]
    rendu = ["  ".join(e.ljust(w) for (_, e), w in zip(colonnes, largeurs, strict=True)).rstrip()]
    rendu += [
        "  ".join(c.ljust(w) for c, w in zip(ligne, largeurs, strict=True)).rstrip()
        for ligne in cellules
    ]
    return "\n".join(rendu)


COLONNES_VM = (
    ("vmid", "VMID"),
    ("name", "NOM"),
    ("status", "ÉTAT"),
    ("node", "NŒUD"),
    ("pool", "POOL"),
    ("cpus", "VCPU"),
    ("memory_mib", "RAM (Mio)"),
    ("disk_gib", "DISQUE (Gio)"),
    ("tags", "ÉTIQUETTES"),
)
