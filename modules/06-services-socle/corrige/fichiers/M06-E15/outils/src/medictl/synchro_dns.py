"""Génération des enregistrements DNS depuis NetBox (M06-E15).

Source : les adresses IP **actives** de NetBox qui portent un ``dns_name`` dans une zone
gérée. Pour chacune : un A dans la zone directe, un PTR dans la zone inverse.

Règles de cohabitation (plusieurs écrivains dans les mêmes zones, ADR-0060) :
- l'outil ne touche qu'aux rrsets qu'il **possède**, reconnus par le compte de leur
  commentaire PowerDNS (``account = medictl-dns``) ; il les crée, les met à jour, et
  supprime ceux qui ne correspondent plus à rien dans NetBox ;
- un rrset qui appartient à un autre écrivain (OpenTofu M06-E14, Kea DDNS M06-E17, un
  humain) n'est jamais modifié : s'il porte déjà la valeur voulue, rien à faire ; sinon
  c'est un **conflit**, signalé ;
- un rrset SANS propriétaire (aucun commentaire : écrit à la main au palier 1) peut être
  ADOPTÉ, mais seulement si son nom figure dans la liste explicite ``adoptables`` ;
- SOA, NS et enregistrements DNSSEC ne sont jamais considérés.

Calcul pur (``planifier``), testé sans réseau ; une écriture par zone.
"""

from __future__ import annotations

import ipaddress
from dataclasses import dataclass, field

COMPTE = "medictl-dns"
TTL = 300
TYPES_GERES = ("A", "PTR")

# Zone directe → zone inverse correspondante (PLAN.md §4.4 et §4.8).
ZONES_DIRECTES = ("par1.medisphere.internal.", "par2.medisphere.internal.")
ZONES_INVERSES = {
    ipaddress.ip_network("10.10.0.0/16"): "10.10.in-addr.arpa.",
    ipaddress.ip_network("10.20.0.0/16"): "20.10.in-addr.arpa.",
}


@dataclass
class Rrset:
    zone: str
    nom: str
    type: str
    contenus: list[str]
    origine: str = ""  # pour le commentaire : d'où vient la valeur dans NetBox


@dataclass
class PlanDns:
    a_ecrire: dict[str, list[dict]] = field(default_factory=dict)  # zone → rrsets du PATCH
    conflits: list[str] = field(default_factory=list)
    resume: list[str] = field(default_factory=list)


def fqdn(nom: str) -> str:
    nom = nom.strip().lower()
    return nom if nom.endswith(".") else nom + "."


def zone_directe(nom: str) -> str | None:
    return next((z for z in ZONES_DIRECTES if nom == z or nom.endswith("." + z)), None)


def zone_inverse(adresse: str) -> str | None:
    ip = ipaddress.ip_address(adresse)
    return next((z for reseau, z in ZONES_INVERSES.items() if ip in reseau), None)


def voulus(ips_netbox: list[dict]) -> tuple[list[Rrset], list[str]]:
    """Rrsets attendus d'après NetBox, et anomalies de données (à corriger dans NetBox)."""
    directs: dict[str, Rrset] = {}
    inverses: dict[str, Rrset] = {}
    anomalies: list[str] = []
    for ip in ips_netbox:
        statut = (ip.get("status") or {}).get("value")
        nom = (ip.get("dns_name") or "").strip()
        if statut != "active" or not nom:
            continue
        adresse = ip["address"].split("/")[0]
        nom = fqdn(nom)
        zone = zone_directe(nom)
        if zone is None:
            anomalies.append(f"{adresse} : {nom} hors des zones gérées, ignoré")
            continue
        origine = f"ipam/ip-addresses/{ip['id']}"
        rr = directs.setdefault(nom, Rrset(zone, nom, "A", [], origine))
        if adresse not in rr.contenus:
            rr.contenus.append(adresse)
        zinv = zone_inverse(adresse)
        if zinv is None:
            continue
        nom_ptr = ipaddress.ip_address(adresse).reverse_pointer + "."
        if nom_ptr in inverses and inverses[nom_ptr].contenus != [nom]:
            premier = inverses[nom_ptr].contenus[0]
            anomalies.append(
                f"{adresse} porte deux noms dans NetBox ({premier} et {nom}) :"
                " un seul PTR possible, le premier est gardé"
            )
            continue
        inverses[nom_ptr] = Rrset(zinv, nom_ptr, "PTR", [nom], origine)
    for rr in directs.values():
        rr.contenus.sort(key=ipaddress.ip_address)
    return sorted([*directs.values(), *inverses.values()], key=lambda r: (r.zone, r.nom)), anomalies


def _proprietaire(rrset: dict) -> str:
    comptes = {c.get("account", "") for c in rrset.get("comments", [])}
    if COMPTE in comptes:
        return COMPTE
    contenus = " ".join(c.get("content", "") for c in rrset.get("comments", []))
    return "opentofu" if "opentofu" in contenus.lower() else (next(iter(comptes), "") or "autre")


def _contenus(rrset: dict) -> list[str]:
    return sorted(r["content"] for r in rrset.get("records", []) if not r.get("disabled"))


def planifier(
    attendus: list[Rrset], zones: dict[str, dict], adoptables: set[str] | frozenset = frozenset()
) -> PlanDns:
    """Compare l'attendu (NetBox) aux zones lues dans PowerDNS.

    adoptables : noms (avec ou sans point final) dont l'outil peut prendre la propriété
    s'ils n'ont aucun propriétaire ; le A et le PTR d'un nom adopté sont repris ensemble.
    """
    adoptables = {fqdn(n) for n in adoptables}
    plan = PlanDns()
    existants: dict[tuple[str, str], tuple[str, dict]] = {}
    for zone, contenu in zones.items():
        for rrset in contenu.get("rrsets", []):
            if rrset["type"] in TYPES_GERES:
                existants[(rrset["name"], rrset["type"])] = (zone, rrset)

    attendus_cles = set()
    for rr in attendus:
        if rr.zone not in zones:
            plan.conflits.append(f"zone {rr.zone} absente de PowerDNS : {rr.nom} ignoré")
            continue
        cle = (rr.nom, rr.type)
        attendus_cles.add(cle)
        _, existant = existants.get(cle, (None, None))
        adoptable = (
            existant is not None
            and not existant.get("comments")
            and (rr.nom in adoptables or (rr.type == "PTR" and rr.contenus[0] in adoptables))
        )
        if existant is not None and _proprietaire(existant) != COMPTE and not adoptable:
            if _contenus(existant) != sorted(rr.contenus):
                plan.conflits.append(
                    f"{rr.nom} {rr.type} appartient à « {_proprietaire(existant)} » "
                    f"({', '.join(_contenus(existant))}) ; NetBox veut {', '.join(rr.contenus)}"
                )
            continue
        if (
            existant is not None
            and _contenus(existant) == sorted(rr.contenus)
            and existant.get("ttl") == TTL
        ):
            continue
        plan.a_ecrire.setdefault(rr.zone, []).append(
            {
                "name": rr.nom,
                "type": rr.type,
                "ttl": TTL,
                "changetype": "REPLACE",
                "records": [{"content": c, "disabled": False} for c in rr.contenus],
                "comments": [
                    {"content": f"généré depuis NetBox ({rr.origine})", "account": COMPTE}
                ],
            }
        )
        verbe = "[adopter]  " if adoptable else "[écrire]   "
        plan.resume.append(f"{verbe} {rr.nom} {rr.type} {' '.join(rr.contenus)}")

    for (nom, typ), (zone, rrset) in sorted(existants.items()):
        if _proprietaire(rrset) == COMPTE and (nom, typ) not in attendus_cles:
            plan.a_ecrire.setdefault(zone, []).append(
                {"name": nom, "type": typ, "changetype": "DELETE"}
            )
            plan.resume.append(f"[supprimer] {nom} {typ} (plus rien dans NetBox)")
    return plan
