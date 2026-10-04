"""Compatibilité InfoGér : anciennes fonctions de l'outil « medictl » de l'infogérant.

Ajouté pour faire tourner les scripts de reprise de l'inventaire InfoGér (PLAT-381).
"""

__version__ = "0.0.9-infoger"


def lister_vms():
    """Ancienne API : renvoyait la liste des VMs depuis l'export CSV d'InfoGér."""
    raise NotImplementedError("export CSV InfoGér non disponible")
