"""medictl : outillage Python de l'équipe Plateforme MédiSphère."""

from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("medictl")
except PackageNotFoundError:  # code lancé sans installation (cas anormal)
    __version__ = "0.0.0+inconnue"
