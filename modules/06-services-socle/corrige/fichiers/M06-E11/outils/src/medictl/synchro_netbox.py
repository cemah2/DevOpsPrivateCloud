"""Synchronisation Proxmox → NetBox (M06-E11).

Qui fait foi pour quoi (ADR-0060) :
- Proxmox dit ce qui **existe et tourne** : VMID, état, vCPU, mémoire, disque, démarrage
  automatique. La synchronisation recopie ces champs dans NetBox ;
- NetBox dit ce qui est **voulu** : nom, rôle, adresses IP, étiquettes. La synchronisation
  ne les modifie jamais sur un objet existant ; elle **signale** les écarts ;
- une VM présente dans NetBox mais absente de Proxmox n'est ni supprimée ni changée :
  c'est soit une VM pas encore créée (OpenTofu, E13), soit une disparition à expliquer.

Le calcul (``planifier``) est une fonction pure, testée sans réseau ; seule
``appliquer`` écrit, objet par objet, et seulement ce qui diffère : un second passage
ne produit aucune écriture (idempotence).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from medictl.sortie import etiquettes

MIO = 1024**2
CHEMIN_VM = "virtualization/virtual-machines/"

# État Proxmox (/cluster/resources) → statut NetBox (VirtualMachineStatusChoices de 4.6).
STATUTS = {"running": "active", "stopped": "offline", "paused": "paused"}

# Étiquettes Proxmox recopiées à la création (jamais retirées ensuite).
PREFIXES_ETIQUETTES = ("role-", "env-m")
ETIQUETTE_SOCLE = "socle"


@dataclass
class Changement:
    """Une action prévue. ``action`` : creer, modifier ou signaler (aucune écriture)."""

    action: str
    nom: str
    vmid: int | None = None
    champs: dict[str, Any] = field(default_factory=dict)
    detail: str = ""
    ident_netbox: int | None = None

    def resume(self) -> str:
        if self.action == "signaler":
            return f"[écart]    {self.nom} : {self.detail}"
        cles = ", ".join(sorted(self.champs)) or "-"
        return f"[{self.action}] {self.nom} (VMID {self.vmid}) : {cles}"


def a_synchroniser(ressource: dict) -> bool:
    """VMs du socle et des environnements de modules ; jamais les templates ni Molecule."""
    if str(ressource.get("template", 0)) == "1":
        return False
    tags = etiquettes(ressource)
    if "molecule" in tags:
        return False
    return ETIQUETTE_SOCLE in tags or any(t.startswith("env-m") for t in tags)


def champs_reels(ressource: dict, config: dict, avec_disque: bool = True) -> dict[str, Any]:
    """Champs NetBox dont Proxmox est la source (unités NetBox : Mio, cf. NetBox 4.5 #21095)."""
    champs: dict[str, Any] = {
        "status": STATUTS.get(str(ressource.get("status")), "offline"),
        "vcpus": float(ressource.get("maxcpu", 0)),
        "memory": int(ressource.get("maxmem", 0)) // MIO,
        "start_on_boot": "on" if str(config.get("onboot", 0)) == "1" else "off",
        "custom_fields": {"vmid": int(ressource["vmid"])},
    }
    if avec_disque:
        champs["disk"] = int(ressource.get("maxdisk", 0)) // MIO
    return champs


def _valeur(vm_netbox: dict, cle: str) -> Any:
    """Valeur comparable d'un champ NetBox (les choix sont des objets {value, label})."""
    valeur = vm_netbox.get(cle)
    if isinstance(valeur, dict) and "value" in valeur:
        return valeur["value"]
    if cle == "vcpus" and valeur is not None:
        return float(valeur)
    return valeur


def differences(vm_netbox: dict, voulus: dict[str, Any]) -> dict[str, Any]:
    """Champs à corriger dans NetBox (seulement ceux qui diffèrent)."""
    a_corriger: dict[str, Any] = {}
    for cle, valeur in voulus.items():
        if cle == "custom_fields":
            actuels = vm_netbox.get("custom_fields") or {}
            ecarts = {k: v for k, v in valeur.items() if actuels.get(k) != v}
            if ecarts:
                a_corriger["custom_fields"] = ecarts  # PATCH partiel : les autres champs restent
        elif _valeur(vm_netbox, cle) != valeur:
            a_corriger[cle] = valeur
    return a_corriger


def planifier(
    vms_proxmox: list[tuple[dict, dict, list[str]]],
    vms_netbox: list[dict],
    *,
    cluster_id: int,
    etiquettes_netbox: set[str],
) -> list[Changement]:
    """Compare Proxmox et NetBox et renvoie les changements, dans un ordre stable.

    vms_proxmox : (ressource de /cluster/resources, configuration, adresses IPv4 de l'agent)
    vms_netbox  : VMs NetBox du cluster (réponse de l'API, objets complets)
    """
    changements: list[Changement] = []
    par_nom = {vm["name"]: vm for vm in vms_netbox}
    par_vmid = {
        (vm.get("custom_fields") or {}).get("vmid"): vm
        for vm in vms_netbox
        if (vm.get("custom_fields") or {}).get("vmid") is not None
    }
    vus: set[str] = set()

    for ressource, config, adresses in sorted(vms_proxmox, key=lambda t: t[0]["vmid"]):
        if not a_synchroniser(ressource):
            continue
        nom, vmid = ressource.get("name", ""), int(ressource["vmid"])
        vus.add(nom)
        existante = par_nom.get(nom)

        if existante is None:
            homonyme = par_vmid.get(vmid)
            if homonyme is not None:
                # Même VMID sous un autre nom : renommage dans Proxmox, ou erreur de saisie.
                vus.add(homonyme["name"])
                changements.append(
                    Changement(
                        "signaler",
                        nom,
                        vmid,
                        detail=f"le VMID {vmid} est porté dans NetBox par « {homonyme['name']} »"
                        " : renommage à confirmer, rien n'est modifié",
                    )
                )
                continue
            voulus = champs_reels(ressource, config)
            tags = [
                t
                for t in etiquettes(ressource)
                if t == ETIQUETTE_SOCLE or t.startswith(PREFIXES_ETIQUETTES)
            ]
            inconnues = sorted(set(tags) - etiquettes_netbox)
            voulus |= {
                "name": nom,
                "cluster": cluster_id,
                "tags": [{"slug": t} for t in tags if t in etiquettes_netbox],
            }
            changements.append(Changement("creer", nom, vmid, voulus))
            if inconnues:
                changements.append(
                    Changement(
                        "signaler",
                        nom,
                        vmid,
                        detail="étiquette(s) absente(s) de NetBox, non posée(s) : "
                        + ", ".join(inconnues),
                    )
                )
            continue

        avec_disque = int(existante.get("virtual_disk_count") or 0) == 0
        a_corriger = differences(existante, champs_reels(ressource, config, avec_disque))
        cluster = (existante.get("cluster") or {}).get("id")
        if cluster != cluster_id:
            a_corriger["cluster"] = cluster_id
        if a_corriger:
            changements.append(
                Changement("modifier", nom, vmid, a_corriger, ident_netbox=existante["id"])
            )

        # Adresse voulue (NetBox) contre adresse vue (agent QEMU) : on signale, on ne corrige pas.
        primaire = ((existante.get("primary_ip4") or {}).get("address") or "").split("/")[0]
        if primaire and adresses and primaire not in adresses:
            changements.append(
                Changement(
                    "signaler",
                    nom,
                    vmid,
                    detail=f"IP primaire NetBox {primaire}, l'agent QEMU voit "
                    + ", ".join(adresses),
                )
            )
        elif not primaire and ressource.get("status") == "running":
            changements.append(
                Changement("signaler", nom, vmid, detail="aucune IP primaire dans NetBox")
            )

    for vm in sorted(vms_netbox, key=lambda v: v["name"]):
        tags_nb = {t.get("slug") for t in vm.get("tags", [])}
        if vm["name"] not in vus and ETIQUETTE_SOCLE in tags_nb:
            changements.append(
                Changement(
                    "signaler",
                    vm["name"],
                    (vm.get("custom_fields") or {}).get("vmid"),
                    detail="présente dans NetBox (socle), absente de Proxmox : décision humaine",
                )
            )
    return changements


@dataclass
class Bilan:
    crees: int = 0
    modifies: int = 0
    ecarts: int = 0


def appliquer(client: Any, changements: list[Changement]) -> Bilan:
    """Écrit les créations et modifications dans NetBox ; les écarts restent des signalements."""
    bilan = Bilan()
    for changement in changements:
        if changement.action == "creer":
            client.creer(CHEMIN_VM, changement.champs)
            bilan.crees += 1
        elif changement.action == "modifier":
            client.modifier(CHEMIN_VM, changement.ident_netbox, changement.champs)
            bilan.modifies += 1
        else:
            bilan.ecarts += 1
    return bilan
