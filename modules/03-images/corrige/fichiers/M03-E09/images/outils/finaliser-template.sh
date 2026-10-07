#!/usr/bin/env bash
# finaliser-template.sh — réglages cloud-init par défaut d'un template doré (M03-E09).
# Appelé par le post-processor « shell-local » de debian13-gold (variable VMID), ou à la main :
#   outils/finaliser-template.sh <VMID>
#
# Packer retire du template les paramètres cloud-init utilisés pendant le build (nameserver,
# searchdomain, ciuser, sshkeys, ipconfig). Sans résolveur sur le template, un clone qui
# n'en précise pas hérite de celui de l'HYPERVISEUR (inaccessible depuis le lab) : on pose
# donc le résolveur du lab. L'utilisateur et la clé restent à la charge de chaque clone.
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=pve.sh disable=SC2154  # PKR_VAR_proxmox_* chargées par pve_charger_acces
. "$(dirname "${BASH_SOURCE[0]}")/pve.sh"

vmid="${1:-${VMID:-}}"
[[ "$vmid" =~ ^90[1-4][0-9]$ ]] || { echo "Usage : $0 <VMID d'un template doré 9010-9049>" >&2; exit 2; }
pve_charger_acces

chemin="/nodes/$PKR_VAR_proxmox_node/qemu/$vmid/config"
conf="$(pve_api GET "$chemin")"
[[ "$(jq -r '.template // 0' <<<"$conf")" == 1 ]] || { echo "$vmid n'est pas un template" >&2; exit 3; }

pve_api PUT "$chemin" nameserver=10.10.20.10 searchdomain=par1.medisphere.internal >/dev/null
conf="$(pve_api GET "$chemin")"
jq -e '.nameserver == "10.10.20.10" and .searchdomain == "par1.medisphere.internal"' <<<"$conf" >/dev/null
echo "template $vmid : résolveur cloud-init 10.10.20.10, domaine par1.medisphere.internal"
