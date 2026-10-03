#!/usr/bin/env bash
# wb-backup-config.sh — Sauvegarde de la configuration de l'hyperviseur vers PBS
# (stockage pbs-par2, namespace par1, groupe host/<nœud>). M00-E30, PLAT-130.
#
# Installé dans /usr/local/sbin/, lancé par wb-backup-config.timer.
# Aucun secret ici : serveur, datastore, jeton et empreinte sont lus dans
# /etc/pve/storage.cfg, le secret dans /etc/pve/priv/storage/<stockage>.pw.
# Si une clé de chiffrement existe pour le stockage (M00-E36), elle est utilisée.
set -euo pipefail
umask 077

STOCKAGE="${STOCKAGE:-pbs-par2}"
STORAGE_CFG=/etc/pve/storage.cfg
SECRET="/etc/pve/priv/storage/${STOCKAGE}.pw"
CLE="/etc/pve/priv/storage/${STOCKAGE}.enc"
TRAVAIL=/var/backups/wb-config

journal() { printf '%s %s\n' "$(date -Is)" "$*"; }

param() {
  awk -v s="$STOCKAGE" -v k="$1" '
    $0 == "pbs: " s   { f = 1; next }
    /^[a-z]+: /       { f = 0 }
    f && $1 == k      { print $2; exit }
  ' "$STORAGE_CFG"
}

serveur="$(param server)"; datastore="$(param datastore)"
utilisateur="$(param username)"; empreinte="$(param fingerprint)"
ns="$(param namespace)"; ns="${ns:-par1}"
port="$(param port)"

if [[ -z "$serveur" || -z "$datastore" || -z "$utilisateur" ]]; then
  journal "ERREUR : stockage $STOCKAGE introuvable ou incomplet dans $STORAGE_CFG" >&2
  exit 1
fi
[[ -r "$SECRET" ]] || { journal "ERREUR : secret $SECRET illisible" >&2; exit 1; }

export PBS_REPOSITORY="${utilisateur}@${serveur}${port:+:$port}:${datastore}"
PBS_PASSWORD="$(head -n 1 "$SECRET")"
export PBS_PASSWORD
[[ -n "$empreinte" ]] && export PBS_FINGERPRINT="$empreinte"

# --- Répertoire de travail : copie cohérente de config.db + inventaires ---------
rm -rf "$TRAVAIL"
mkdir -p "$TRAVAIL"

# Copie à chaud cohérente de la base de pmxcfs (API de sauvegarde en ligne de SQLite)
sqlite3 /var/lib/pve-cluster/config.db ".backup '$TRAVAIL/config.db'"
sqlite3 "$TRAVAIL/config.db" 'PRAGMA integrity_check;' | grep -qx ok \
  || { journal "ERREUR : copie de config.db corrompue" >&2; exit 1; }

# Inventaires utiles à une reconstruction (pas indispensables, mais précieux à 3 h du matin)
{
  pveversion -v
} > "$TRAVAIL/pveversion.txt" 2>&1 || true
dpkg --get-selections > "$TRAVAIL/paquets.txt" 2>&1 || true
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL > "$TRAVAIL/lsblk.txt" 2>&1 || true
ip -d address > "$TRAVAIL/ip-address.txt" 2>&1 || true
ip route > "$TRAVAIL/ip-route.txt" 2>&1 || true
pvesm status > "$TRAVAIL/pvesm-status.txt" 2>&1 || true
qm list > "$TRAVAIL/qm-list.txt" 2>&1 || true
if command -v zpool >/dev/null 2>&1; then
  zpool status > "$TRAVAIL/zpool-status.txt" 2>&1 || true
  zfs list -o name,used,avail,mountpoint > "$TRAVAIL/zfs-list.txt" 2>&1 || true
fi
if command -v lvs >/dev/null 2>&1; then
  { vgs; lvs; } > "$TRAVAIL/lvm.txt" 2>&1 || true
fi

# --- Sauvegarde -------------------------------------------------------------------
args=(
  etc.pxar:/etc
  root.pxar:/root
  wbconfig.pxar:"$TRAVAIL"
  --include-dev /etc/pve           # /etc/pve est un montage FUSE distinct : à inclure explicitement
  --ns "$ns"
  --backup-type host
  --backup-id "$(hostname)"
)
if [[ -s "$CLE" ]]; then
  args+=(--keyfile "$CLE")
  journal "Chiffrement : clé $CLE"
else
  journal "Chiffrement : aucune clé (sauvegarde en clair)"
fi

journal "Début : $PBS_REPOSITORY, namespace $ns"
proxmox-backup-client backup "${args[@]}"
journal "Fin : succès"
