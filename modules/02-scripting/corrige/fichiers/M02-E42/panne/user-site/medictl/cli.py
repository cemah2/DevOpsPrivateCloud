"""Interface en ligne de commande du prototype medictl 0.1.0 (argparse)."""

import argparse
import configparser
import os
import sys

from medictl import __version__

CONFIG = os.path.expanduser("~/.medictl.ini")


def main() -> int:
    parser = argparse.ArgumentParser(prog="medictl")
    parser.add_argument("--version", action="version", version=f"medictl {__version__}")
    sub = parser.add_subparsers(dest="objet", required=True)
    vm = sub.add_parser("vm", help="machines virtuelles")
    vm_sub = vm.add_subparsers(dest="action", required=True)
    vm_sub.add_parser("list", help="lister les VMs")
    args = parser.parse_args()

    conf = configparser.ConfigParser()
    if not conf.read(CONFIG):
        print(f"medictl {__version__} : configuration {CONFIG} introuvable", file=sys.stderr)
        return 1
    print(f"medictl {__version__} : {args.objet} {args.action} non disponible dans ce prototype")
    return 1


if __name__ == "__main__":
    sys.exit(main())
