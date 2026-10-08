# Copyright: Équipe Plateforme MédiSphère
# Filtres nftables de la collection medisphere.socle (M04-E18 ; protocole vrrp ajouté en M07-E25).
# Documentation : regle_nft.yml (fichier voisin, lu par ansible-doc).
"""Transforme les flux de la matrice des flux en règles nftables."""

from __future__ import annotations

from collections.abc import Mapping

from ansible.errors import AnsibleFilterError

CHAMPS = {
    "entree", "sortie", "source", "destination", "proto",
    "ports", "ports_source", "icmp", "action", "motif", "ref",
}
PROTOCOLES = {"tcp", "udp", "tcp_udp", "icmp", "vrrp"}
# Protocoles IP sans ports, rendus par leur numéro (indépendant de /etc/protocols).
PROTOCOLES_SANS_PORTS = {"vrrp": 112}
ACTIONS = {"accept", "drop", "reject"}
COMMENTAIRE_MAX_OCTETS = 128  # limite de nftables pour un commentaire


def _ensemble(valeur):
    """« x » pour une valeur seule, « { a, b } » pour une liste."""
    if isinstance(valeur, (list, tuple)):
        if not valeur:
            raise AnsibleFilterError("regle_nft : liste vide")
        return "{ " + ", ".join(str(v) for v in valeur) + " }"
    return str(valeur)


def regle_nft(flux):
    """Rend une règle nftables (une ligne) à partir d'un flux de la matrice."""
    if not isinstance(flux, Mapping):
        raise AnsibleFilterError(f"regle_nft : un dictionnaire est attendu, pas {type(flux).__name__}")

    inconnus = sorted(set(flux) - CHAMPS)
    if inconnus:
        raise AnsibleFilterError(f"regle_nft : champ(s) inconnu(s) {inconnus} (faute de frappe ?)")

    motif = str(flux.get("motif", "")).strip()
    if not motif:
        raise AnsibleFilterError("regle_nft : chaque flux doit avoir un motif")
    commentaire = motif + (f" ({flux['ref']})" if flux.get("ref") else "")
    if '"' in commentaire:
        raise AnsibleFilterError(f"regle_nft : guillemet interdit dans le motif : {motif}")
    if len(commentaire.encode("utf-8")) > COMMENTAIRE_MAX_OCTETS:
        raise AnsibleFilterError(f"regle_nft : commentaire de plus de {COMMENTAIRE_MAX_OCTETS} octets : {motif}")

    criteres = []
    for champ, mot_cle in (
        ("entree", "iifname"),
        ("sortie", "oifname"),
        ("source", "ip saddr"),
        ("destination", "ip daddr"),
    ):
        if champ in flux:
            criteres.append(f"{mot_cle} {_ensemble(flux[champ])}")

    proto = flux.get("proto")
    a_des_ports = "ports" in flux or "ports_source" in flux
    if proto is None:
        if a_des_ports or "icmp" in flux:
            raise AnsibleFilterError(f"regle_nft : ports ou type ICMP sans proto ({motif})")
    elif proto not in PROTOCOLES:
        raise AnsibleFilterError(f"regle_nft : proto « {proto} » inconnu (attendu : {sorted(PROTOCOLES)})")
    elif proto in PROTOCOLES_SANS_PORTS:
        if a_des_ports or "icmp" in flux:
            raise AnsibleFilterError(f"regle_nft : pas de ports ni de type ICMP avec {proto} ({motif})")
        criteres.append(f"meta l4proto {PROTOCOLES_SANS_PORTS[proto]}")
    elif proto == "icmp":
        if a_des_ports:
            raise AnsibleFilterError(f"regle_nft : pas de ports avec ICMP ({motif})")
        criteres.append(f"icmp type {_ensemble(flux.get('icmp', 'echo-request'))}")
    else:
        prefixe = "th" if proto == "tcp_udp" else proto
        if proto == "tcp_udp":
            criteres.append("meta l4proto { tcp, udp }")
        elif not a_des_ports:
            criteres.append(f"meta l4proto {proto}")
        if "ports_source" in flux:
            criteres.append(f"{prefixe} sport {_ensemble(flux['ports_source'])}")
        if "ports" in flux:
            criteres.append(f"{prefixe} dport {_ensemble(flux['ports'])}")

    action = flux.get("action", "accept")
    if action not in ACTIONS:
        raise AnsibleFilterError(f"regle_nft : action « {action} » inconnue (attendu : {sorted(ACTIONS)})")

    return " ".join(criteres + [action, f'comment "{commentaire}"'])


class FilterModule:
    """Filtres nftables de medisphere.socle."""

    def filters(self):
        return {"regle_nft": regle_nft}
