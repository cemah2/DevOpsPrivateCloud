"""Garde-fous de medictl (M02-E16).

Règles (PLAN.md §4.6) : medictl ne crée et ne détruit que des VMs jetables,
VMID 2000-2999 (environnements des modules) ou 5000-5999 (sandbox), membres
du pool « lab ». Jamais le socle (1000-1099), jamais un template (9000-9099),
jamais une VM hors du pool. Tout refus lève RefusGardeFou (code 3) AVANT la
moindre écriture.

Ces fonctions sont pures (aucun appel réseau) : elles se testent sans Proxmox.
"""

from __future__ import annotations

import re

from medictl.erreurs import RefusGardeFou

POOL = "lab"
PLAGES_AUTORISEES = (range(2000, 3000), range(5000, 6000))
PLAGES_PROTEGEES = {
    "socle permanent": range(1000, 1100),
    "templates": range(9000, 9100),
}
# Nom DNS d'un seul niveau, comme l'exige Proxmox pour le nom d'une VM.
_NOM = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")


def verifier_vmid_modifiable(vmid: int) -> None:
    for libelle, plage in PLAGES_PROTEGEES.items():
        if vmid in plage:
            raise RefusGardeFou(
                f"VMID {vmid} : plage protégée ({libelle}, {plage.start}-{plage.stop - 1})"
            )
    if not any(vmid in plage for plage in PLAGES_AUTORISEES):
        raise RefusGardeFou(f"VMID {vmid} hors des plages autorisées (2000-2999, 5000-5999)")


def verifier_vm_modifiable(ressource: dict) -> None:
    """Contrôle une VM existante (entrée de /cluster/resources) avant destruction."""
    vmid = int(ressource["vmid"])
    verifier_vmid_modifiable(vmid)
    if ressource.get("type") != "qemu":
        raise RefusGardeFou(f"{vmid} n'est pas une VM QEMU")
    if str(ressource.get("template", 0)) == "1":
        raise RefusGardeFou(f"{vmid} est un template")
    if ressource.get("pool") != POOL:
        raise RefusGardeFou(f"VM {vmid} hors du pool {POOL}")


def verifier_source_clonage(ressource: dict) -> None:
    """Le modèle d'une création doit être un template du pool lab, de la plage 9000-9099."""
    vmid = int(ressource["vmid"])
    if vmid not in PLAGES_PROTEGEES["templates"]:
        raise RefusGardeFou(f"{vmid} n'est pas dans la plage des templates (9000-9099)")
    if str(ressource.get("template", 0)) != "1":
        raise RefusGardeFou(f"{vmid} n'est pas un template")
    if ressource.get("pool") != POOL:
        raise RefusGardeFou(f"template {vmid} hors du pool {POOL}")


def verifier_nom(nom: str) -> None:
    if not _NOM.match(nom):
        raise RefusGardeFou(
            f"nom « {nom} » invalide : minuscules, chiffres et tirets, 63 caractères au plus"
        )
