#!/usr/bin/env bash
# capi/preflight-pve.sh — vérification préalable CAPMOX / Proxmox VE 9 (M18-E08, PLAT-1908).
#
#   admin@m18-dev01:~/src/distributions$ capi/preflight-pve.sh
#
# Rejoue, AVEC LE JETON DE CAPMOX (wb-capi@pve!capi) et depuis la machine qui portera le
# contrôleur, les appels d'API dont CAPMOX v0.9.1 a besoin, sur une VM jetable :
#   version, lecture des ressources, état du nœud, téléversement et suppression d'une ISO dans
#   capi-iso, clonage d'un template du pool lab vers le VMID 5189, configuration, suppression.
# Toute réponse inattendue arrête le script : c'est le critère de repli vers CAPD.
# Lecture seule sur Proxmox, SAUF la VM 5189 et l'ISO d'essai, supprimées à la fin (et à l'échec).
#
# Entrées : ~/.config/workbook/pve-capi.env (PROXMOX_URL, PROXMOX_TOKEN, PROXMOX_SECRET),
#           NOEUD (nom du nœud Proxmox), TEMPLATE (VMID d'un template du pool lab, défaut 9000).
set -euo pipefail

ENV_FILE="${ENV_FILE:-$HOME/.config/workbook/pve-capi.env}"
NOEUD="${NOEUD:?indique le nœud Proxmox : NOEUD=<NOEUD> $0}"
TEMPLATE="${TEMPLATE:-9000}"
VMID_ESSAI="${VMID_ESSAI:-5189}"
STOCKAGE_ISO="${STOCKAGE_ISO:-capi-iso}"
STOCKAGE_VM="${STOCKAGE_VM:-local-nvme}"

[[ "$(stat -c %a "$ENV_FILE")" == 600 ]] || { echo "$ENV_FILE doit être en 600" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${PROXMOX_URL:?}" "${PROXMOX_TOKEN:?}" "${PROXMOX_SECRET:?}"
API="${PROXMOX_URL%/}/api2/json"

# En-tête d'authentification dans un fichier 600 (jamais sur la ligne de commande : ps le montrerait).
entete="$(mktemp)"; chmod 600 "$entete"
iso="$(mktemp --suffix=.iso)"
CLONE_CREE=0
ISO_CREEE=0
# Nettoyage : seulement ce que CE script a créé (jamais une VM 5189 qui existait avant).
nettoyer() {
  if (( CLONE_CREE )); then
    pve DELETE "/nodes/$NOEUD/qemu/$VMID_ESSAI?purge=1&destroy-unreferenced-disks=1" >/dev/null 2>&1 || true
  fi
  if (( ISO_CREEE )); then
    pve DELETE "/nodes/$NOEUD/storage/$STOCKAGE_ISO/content/$STOCKAGE_ISO:iso/preflight-capi.iso" >/dev/null 2>&1 || true
  fi
  rm -f "$entete" "$iso"
}
trap nettoyer EXIT
printf 'Authorization: PVEAPIToken=%s=%s\n' "$PROXMOX_TOKEN" "$PROXMOX_SECRET" > "$entete"

# pve MÉTHODE CHEMIN [options curl…] — TLS VÉRIFIÉ (ancre de pve01 dans le magasin du système).
pve() {
  local m="$1" c="$2"; shift 2
  curl -sS --fail-with-body -X "$m" -H "@$entete" "$@" "$API$c"
}
etape() { printf '\n== %s\n' "$*"; }
attendre_tache() { # attendre_tache UPID
  local upid="$1" statut
  for _ in $(seq 1 120); do
    statut="$(pve GET "/nodes/$NOEUD/tasks/$(jq -rn --arg u "$upid" '$u|@uri')/status")"
    if [[ "$(jq -r .data.status <<<"$statut")" == stopped ]]; then
      [[ "$(jq -r .data.exitstatus <<<"$statut")" == OK ]] || { echo "tâche en échec : $statut" >&2; return 1; }
      return 0
    fi
    sleep 2
  done
  echo "tâche trop longue : $upid" >&2; return 1
}

etape "Version de Proxmox VE (TLS vérifié, jeton accepté)"
pve GET /version | jq -r '.data | "Proxmox VE \(.version) (\(.release))"'

etape "Ressources visibles par le jeton (pool lab seulement)"
pve GET "/cluster/resources?type=vm" | jq -r '.data[] | "\(.vmid)\t\(.name)\t\(.pool // "-")\t\(.template // 0)"' | sort -n | head -20

etape "État du nœud (Sys.Audit : mémoire pour l'ordonnanceur de CAPMOX)"
pve GET "/nodes/$NOEUD/status" | jq -r '.data.memory | "mémoire : \(.total) octets, libre \(.free)"'

etape "Stockages visibles : CAPMOX téléverse dans le PREMIER stockage « iso » qu'il voit"
pve GET "/nodes/$NOEUD/storage?content=iso" | jq -r '.data[].storage'

etape "Téléversement puis suppression d'une ISO dans $STOCKAGE_ISO (Datastore.AllocateTemplate)"
genisoimage -quiet -V cidata -o "$iso" /dev/null 2>/dev/null || dd if=/dev/zero of="$iso" bs=1k count=64 status=none
ISO_CREEE=1
upid="$(pve POST "/nodes/$NOEUD/storage/$STOCKAGE_ISO/upload" -F content=iso -F "filename=@$iso;filename=preflight-capi.iso" | jq -r .data)"
attendre_tache "$upid"
pve DELETE "/nodes/$NOEUD/storage/$STOCKAGE_ISO/content/$STOCKAGE_ISO:iso/preflight-capi.iso" >/dev/null
ISO_CREEE=0

if pve GET "/cluster/resources?type=vm" | jq -e --argjson id "$VMID_ESSAI" '.data[] | select(.vmid == $id)' >/dev/null; then
  echo "Le VMID $VMID_ESSAI existe déjà : rien n'est cloné ni supprimé. Libère-le ou change VMID_ESSAI." >&2
  exit 1
fi
etape "Clonage complet du template $TEMPLATE vers $VMID_ESSAI dans le pool lab (VM.Clone, VM.Allocate, AllocateSpace)"
upid="$(pve POST "/nodes/$NOEUD/qemu/$TEMPLATE/clone" -d newid="$VMID_ESSAI" -d name=preflight-capi \
  -d pool=lab -d full=1 -d storage="$STOCKAGE_VM" | jq -r .data)"
CLONE_CREE=1
attendre_tache "$upid"

etape "Configuration de la VM clonée (CPU, mémoire, carte sur vk8s, étiquettes)"
pve PUT "/nodes/$NOEUD/qemu/$VMID_ESSAI/config" -d cores=2 -d memory=2048 \
  -d "net0=virtio,bridge=vk8s" -d "tags=env-m18;preflight" >/dev/null
pve GET "/nodes/$NOEUD/qemu/$VMID_ESSAI/config" | jq -r '.data | "cores=\(.cores) memory=\(.memory) net0=\(.net0) tags=\(.tags)"'

etape "Suppression de la VM d'essai"
upid="$(pve DELETE "/nodes/$NOEUD/qemu/$VMID_ESSAI?purge=1&destroy-unreferenced-disks=1" | jq -r .data)"
attendre_tache "$upid"
CLONE_CREE=0

printf '\nVérification préalable : tous les appels ont réussi avec le jeton wb-capi@pve!capi.\n'
