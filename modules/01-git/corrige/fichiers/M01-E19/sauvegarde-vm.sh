#!/usr/bin/env bash
# sauvegarde-vm.sh — sauvegarde une VM du lab vers PBS (outil de l'équipe MédiAgenda).
set -euo pipefail

STOCKAGE="pbs-par2"

verifier_vmid() {
  [[ "$1" =~ ^[0-9]+$ ]] || { echo "VMID invalide : $1" >&2; exit 2; }
  (( $1 >= 1000 && $1 <= 9099 )) || { echo "VMID hors des plages du workbook : $1" >&2; exit 2; }
}

sauvegarder() {
  local vmid="$1"
  verifier_vmid "$vmid"
  vzdump "$vmid" --storage "$STOCKAGE" --mode snapshot \
    || { echo "échec de vzdump pour la VM $vmid (voir le journal de la tâche sur pve01)" >&2; exit 1; }
}

[[ $# -eq 1 ]] || { echo "Usage : $0 VMID" >&2; exit 2; }
sauvegarder "$1"
