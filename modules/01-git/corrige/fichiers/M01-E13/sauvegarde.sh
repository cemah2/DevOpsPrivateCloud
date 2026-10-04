#!/usr/bin/env bash
# sauvegarde.sh — lance vzdump pour une liste de VMs du lab.
# Usage : sauvegarde.sh VMID...   (SIMULATION=1 pour afficher les commandes sans les lancer)
set -euo pipefail

STOCKAGE="pbs-par2"
MODE="snapshot"
SIMULATION="${SIMULATION:-0}"

lancer() {
  if [[ "$SIMULATION" == 1 ]]; then echo "+ $*"; else "$@"; fi
}

controler_vmids() {
  local v
  (( $# > 0 )) || { echo "Usage : $0 VMID..." >&2; exit 2; }
  for v in "$@"; do
    [[ "$v" =~ ^(1[0-9]{3}|2[0-9]{3}|5[0-9]{3})$ ]] || { echo "VMID hors des plages du lab : $v" >&2; exit 2; }
  done
}

verifier_stockage() {
  lancer pvesm status --storage "$STOCKAGE" >/dev/null || { echo "stockage $STOCKAGE indisponible" >&2; exit 1; }
}

# --- Contrôles préalables ---
controler_vmids "$@"
verifier_stockage

# --- Sauvegarde ---
echo "Sauvegarde de $# VM(s) vers $STOCKAGE"
for vmid in "$@"; do
  lancer vzdump "$vmid" --storage "$STOCKAGE" --mode "$MODE"
done
