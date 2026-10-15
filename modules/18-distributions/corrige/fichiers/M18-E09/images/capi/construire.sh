#!/usr/bin/env bash
# capi/construire.sh — construit le template Cluster API 9060 avec image-builder (M18-E09, PLAT-1909).
#
#   admin@m18-dev01:~/src/images$ capi/construire.sh            construit (≈ 25 à 40 min)
#   admin@m18-dev01:~/src/images$ capi/construire.sh --valider  « make validate-… » seulement
#   admin@m18-dev01:~/src/images$ VARS=capi/ubuntu-2404-k136-2.json ETIQUETTES="capi;k8s-v1.36.5" capi/construire.sh
#
# image-builder v0.1.55, cloné À L'ÉTIQUETTE dans ~/m18/image-builder (hors dépôt). Deux
# corrections locales de son gabarit Packer Proxmox, appliquées par jq et AFFICHÉES :
#   1. insecure_skip_tls_verify: true est écrit EN DUR dans packer/proxmox/packer.json : on le
#      remet à false (règle 4 du module ; l'ancre de pve01 est dans le magasin de m18-dev01) ;
#   2. pas de « pool » : le jeton wb-packer n'a de droits que sur le pool lab (M03-E02) ; sans
#      pool, la création de la VM de build est refusée. On ajoute pool = lab et des étiquettes.
# Identifiants : ~/.config/workbook/pve-packer.env (wb-packer@pve!packer, M03), lu ici, jamais
# affiché. Attention à la convention d'image-builder (PROXMOX_USERNAME = identifiant du JETON,
# PROXMOX_TOKEN = son SECRET), inverse de celle de CAPMOX.
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IB_VERSION="${IB_VERSION:-v0.1.55}"
IB_DIR="${IB_DIR:-$HOME/m18/image-builder}"
ENV_FILE="${ENV_FILE:-$HOME/.config/workbook/pve-packer.env}"
NOEUD="${NOEUD:?indique le nœud Proxmox : NOEUD=<NOEUD> $0}"
ETIQUETTES="${ETIQUETTES:-capi;k8s-v1.36.4}"

[[ "$(stat -c %a "$ENV_FILE")" == 600 ]] || { echo "$ENV_FILE doit être en 600" >&2; exit 1; }
# pve-packer.env (M03-E02) : PKR_VAR_proxmox_url, PKR_VAR_proxmox_username, PKR_VAR_proxmox_token.
# shellcheck disable=SC1090
source "$ENV_FILE"

if [[ ! -d "$IB_DIR/.git" ]]; then
  git clone --depth 1 --branch "$IB_VERSION" https://github.com/kubernetes-sigs/image-builder.git "$IB_DIR"
fi
[[ "$(git -C "$IB_DIR" describe --tags --exact-match)" == "$IB_VERSION" ]] \
  || { echo "$IB_DIR n'est pas à l'étiquette $IB_VERSION" >&2; exit 1; }

gabarit="$IB_DIR/images/capi/packer/proxmox/packer.json"
git -C "$IB_DIR" checkout -- images/capi/packer/proxmox/packer.json
jq --arg tags "$ETIQUETTES" \
  '.builders[0].insecure_skip_tls_verify = false | .builders[0].pool = "lab" | .builders[0].tags = $tags' \
  "$gabarit" > "$gabarit.nouveau"
mv "$gabarit.nouveau" "$gabarit"
echo "Corrections locales du gabarit Packer d'image-builder :"
git -C "$IB_DIR" --no-pager diff --stat
git -C "$IB_DIR" --no-pager diff -U0 images/capi/packer/proxmox/packer.json

export PROXMOX_URL="${PKR_VAR_proxmox_url:?}"          # https://<IP-PVE01>:8006/api2/json
export PROXMOX_USERNAME="${PKR_VAR_proxmox_username:?}" # wb-packer@pve!packer
export PROXMOX_TOKEN="${PKR_VAR_proxmox_token:?}"       # secret du jeton
export PROXMOX_NODE="$NOEUD"
export PROXMOX_ISO_POOL=hdd-bulk
export PROXMOX_BRIDGE=vsandbox
export PROXMOX_STORAGE_POOL=local-nvme
# VARS : fichier de variables de la version à construire (M18-E13 : capi/ubuntu-2404-k136-2.json).
PACKER_VAR_FILES="$(realpath "${VARS:-$ICI/ubuntu-2404-k136.json}")"   # absolu : make tourne dans le clone
export PACKER_VAR_FILES

cd "$IB_DIR/images/capi"
if [[ "${1:-}" == "--valider" ]]; then
  make validate-proxmox-ubuntu-2404
else
  make build-proxmox-ubuntu-2404
fi
