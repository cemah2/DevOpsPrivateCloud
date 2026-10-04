"""Exceptions de medictl, chacune porteuse de son code de sortie.

Codes communs à tous les outils de plateforme/outils :
0 succès, 1 erreur, 2 usage (géré par Typer), 3 refus d'un garde-fou.
"""


class ErreurMedictl(Exception):
    """Erreur prévue : message clair pour l'opérateur, sans pile d'appels."""

    code = 1


class ConfigError(ErreurMedictl):
    """Configuration absente, incomplète ou dangereuse (droits du fichier)."""


class ErreurApi(ErreurMedictl):
    """Échec d'un appel à l'API Proxmox (réseau, TLS, HTTP, tâche en échec)."""


class VmIntrouvable(ErreurMedictl):
    """VMID inexistant, ou invisible pour le jeton (hors du pool lab)."""


class RefusGardeFou(ErreurMedictl):
    """Action refusée par un garde-fou : rien n'a été modifié."""

    code = 3
