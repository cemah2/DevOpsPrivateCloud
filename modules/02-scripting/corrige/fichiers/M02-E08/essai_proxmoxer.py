"""Le même travail avec proxmoxer et le module medictl.pve (M02-E08, étape 3).

Lancement, depuis la copie de travail du projet : uv run python ~/m02/e08/essai_proxmoxer.py
"""

import sys

import requests
from medictl.pve import ConfigError, charger_config, connexion
from proxmoxer import ResourceException


def main() -> int:
    try:
        cfg = charger_config()
    except ConfigError as exc:
        print(f"configuration : {exc}", file=sys.stderr)
        return 2
    print(f"configuration lue : {cfg!r}")  # le secret n'apparaît pas (repr=False)

    pve = connexion(cfg)
    try:
        print(f"Proxmox VE {pve.version.get()['version']}")
        vms = pve.cluster.resources.get(type="vm")
        for vm in sorted(vms, key=lambda v: v["vmid"]):
            if vm.get("pool") == "lab" and vm["type"] == "qemu" and not vm.get("template"):
                print(f"{vm['vmid']:>5}  {vm['name']:<20} {vm['status']}")
        # Appel volontairement refusé : le jeton n'a aucun droit sur le nœud.
        pve.nodes(cfg.node).status.get()
    except ResourceException as exc:
        # str(exc) = « code statut : motif » ; Proxmox donne le motif dans la ligne de statut.
        print(f"refus de l'API : {exc}", file=sys.stderr)
        return 1
    except requests.exceptions.SSLError as exc:
        print(f"certificat refusé : {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
