#!/usr/bin/env bash
# verif-pbs.sh — vérifie l'âge de la dernière sauvegarde de chaque VM sur PBS.
# Usage : verif-pbs.sh [--datastore NOM] [--seuil-heures N]
set -euo pipefail

DATASTORE="ds-lab"
SEUIL_HEURES=26
PBS_HOTE="pbs01.par2.medisphere.internal"

usage() { echo "Usage : $0 [--datastore NOM] [--seuil-heures N]" >&2; exit 2; }

while (( $# > 0 )); do
  case "$1" in
    --datastore)    DATASTORE="${2:?}"; shift 2 ;;
    --seuil-heures) SEUIL_HEURES="${2:?}"; shift 2 ;;
    *)              usage ;;
  esac
done

if [[ -z "${PBS_PASSWORD:-}" ]]; then
  echo "variable PBS_PASSWORD absente (secret à charger depuis ~/.config/workbook)" >&2
  exit 1
fi

export PBS_REPOSITORY="root@pam@${PBS_HOTE}:${DATASTORE}"
maintenant="$(date +%s)"
proxmox-backup-client snapshot list --output-format json \
  | jq -r --argjson now "$maintenant" --argjson seuil "$SEUIL_HEURES" '
      group_by(."backup-type" + "/" + ."backup-id")[]
      | max_by(."backup-time")
      | select(($now - ."backup-time") > $seuil * 3600)
      | "\(."backup-type")/\(."backup-id") : dernière sauvegarde trop ancienne"'
