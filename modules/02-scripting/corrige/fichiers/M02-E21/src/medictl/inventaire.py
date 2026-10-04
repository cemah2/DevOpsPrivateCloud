"""Inventaire du socle généré depuis l'API Proxmox (M02-E21).

Principes :
- source de vérité = l'API (étiquette Proxmox « socle »), pas un tableau tenu à la main ;
- sortie DÉTERMINISTE : même lab → même texte, octet pour octet (pas d'horodatage
  dans le bloc, tri par VMID) ; une régénération sans changement ne produit
  aucun diff, un diff signale donc un vrai changement ;
- le bloc généré est délimité par des balises : le reste du fichier
  (texte rédigé par l'équipe) n'est jamais touché.

Contrat JSON (relu par d'autres outils) : liste d'objets
  {vmid, name, role, status, node, cpus, memory_mib, disk_gib, ipv4, tags}
"""

from __future__ import annotations

from medictl.sortie import en_tableau, etiquettes, resume_vm

DEBUT = "<!-- medictl:inventaire:debut (bloc généré : ne pas modifier à la main) -->"
FIN = "<!-- medictl:inventaire:fin -->"
ETIQUETTE_SOCLE = "socle"


def role(ressource: dict) -> str:
    """Rôle tiré de l'étiquette role-<rôle> (PLAN.md §4.8)."""
    roles = [t.removeprefix("role-") for t in etiquettes(ressource) if t.startswith("role-")]
    return ",".join(roles) or "-"


def collecter(client, etiquette: str = ETIQUETTE_SOCLE) -> list[dict]:
    """Une entrée par VM portant l'étiquette ; adresses lues par l'agent QEMU."""
    entrees = []
    for ressource in client.vms():
        if etiquette not in etiquettes(ressource):
            continue
        resume = resume_vm(ressource)
        en_marche = ressource.get("status") == "running"
        entrees.append(
            {
                "vmid": resume["vmid"],
                "name": resume["name"],
                "role": role(ressource),
                "status": resume["status"],
                "node": resume["node"],
                "cpus": resume["cpus"],
                "memory_mib": resume["memory_mib"],
                "disk_gib": resume["disk_gib"],
                "ipv4": client.adresses_ipv4(ressource) if en_marche else [],
                "tags": resume["tags"],
            }
        )
    return sorted(entrees, key=lambda e: e["vmid"])


COLONNES = (
    ("vmid", "VMID"),
    ("name", "Nom"),
    ("role", "Rôle"),
    ("status", "État"),
    ("cpus", "vCPU"),
    ("memory_mib", "RAM (Mio)"),
    ("disk_gib", "Disque (Gio)"),
    ("ipv4", "IPv4 (agent QEMU)"),
)


def en_markdown(entrees: list[dict]) -> str:
    entetes = [e for _, e in COLONNES]
    lignes = [
        "| " + " | ".join(entetes) + " |",
        "|" + "|".join("---" for _ in entetes) + "|",
    ]
    for entree in entrees:
        cellules = []
        for cle, _ in COLONNES:
            valeur = entree[cle]
            if isinstance(valeur, list):
                valeur = ", ".join(valeur) or "—"
            cellules.append(f"`{valeur}`" if cle == "name" else str(valeur))
        lignes.append("| " + " | ".join(cellules) + " |")
    return "\n".join([DEBUT, "", *lignes, "", FIN])


def en_texte(entrees: list[dict]) -> str:
    return en_tableau(entrees, COLONNES)


def remplacer_bloc(document: str, bloc: str) -> str:
    """Remplace le bloc balisé ; l'ajoute en fin de document s'il n'existe pas.
    Refuse un document aux balises incohérentes plutôt que de le saccager."""
    debut, fin = document.count(DEBUT), document.count(FIN)
    if debut == fin == 0:
        return document.rstrip("\n") + "\n\n" + bloc + "\n"
    if debut != 1 or fin != 1 or document.index(DEBUT) > document.index(FIN):
        raise ValueError("balises medictl:inventaire absentes, dupliquées ou dans le désordre")
    avant = document[: document.index(DEBUT)]
    apres = document[document.index(FIN) + len(FIN) :]
    return avant + bloc + apres
