"""medictl — CLI d'exploitation du lab MédiSphère (plateforme/outils, module 02)."""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("medictl")
except PackageNotFoundError:  # code lancé hors d'un paquet installé
    __version__ = "0.0.0+inconnue"
