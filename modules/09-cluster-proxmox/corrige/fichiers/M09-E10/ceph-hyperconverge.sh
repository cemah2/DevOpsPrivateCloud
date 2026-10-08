#!/usr/bin/env bash
# ceph-hyperconverge.sh — Ceph hyperconvergé du cluster hv-par1 (M09-E10), après « pveceph install ».
#
# À lancer en root sur hv01. Agit sur les trois nœuds par SSH (clés root du cluster, posées par
# pvecm à la formation du cluster). Rejouable : ce qui existe déjà est sauté.
#
# Prérequis (étapes 1-2 de l'énoncé, à faire à la main, car pveceph install est interactif) :
#   root@hvNN:~# pveceph install --repository no-subscription --version squid
#
# Disques OSD : désignés par /dev/disk/by-id (stable), pas par /dev/sdX : numéros de série fixés par
# OpenTofu en M09-E03 (hvNN-osd1, hvNN-osd2 : les deux disques de 48 Go sur ssd-lab). Le script
# REFUSE un disque qui n'a pas exactement la taille attendue, qui porte des partitions, une
# signature de système de fichiers, ou qui est déjà utilisé (LVM, ZFS).
#   SERIES_OSD="osd1 osd2"   → /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_<nœud>-osd1, …
#   TAILLE_OSD_OCTETS=51539607552   (48 Gio)
set -euo pipefail

NOEUDS=(hv01 hv02 hv03)
RESEAU_PUBLIC="10.10.30.0/24"
RESEAU_CLUSTER="10.10.31.0/24"
POOL="ceph-vm"
MEMOIRE_OSD=1073741824 # 1 Gio, en octets
read -ra SERIES_OSD <<<"${SERIES_OSD:-osd1 osd2}"
TAILLE_OSD_OCTETS="${TAILLE_OSD_OCTETS:-51539607552}"

[[ "$(hostname -s)" == hv01 ]] || { echo "à lancer sur hv01" >&2; exit 1; }

sur() { # sur NŒUD COMMANDE… — exécute sur un nœud (localement si c'est hv01)
  local n="$1"; shift
  if [[ "$n" == "$(hostname -s)" ]]; then bash -c "$*"; else ssh -o BatchMode=yes "root@$n" -- "$@"; fi
}

# --- 0. Contrôles préalables ---------------------------------------------------------------------
pvecm status | grep -q 'Quorate:.*Yes' || { echo "cluster sans quorum : arrêt" >&2; exit 1; }
for n in "${NOEUDS[@]}"; do
  sur "$n" 'ceph --version' | grep -q 'squid' \
    || { echo "$n : Ceph Squid absent (pveceph install --repository no-subscription --version squid)" >&2; exit 1; }
done

# --- 1. Configuration initiale (une seule fois pour tout le cluster) -----------------------------
if [[ -f /etc/pve/ceph.conf ]]; then
  echo "== /etc/pve/ceph.conf existe déjà : init sautée"
else
  pveceph init --network "$RESEAU_PUBLIC" --cluster-network "$RESEAU_CLUSTER"
fi

# --- 2. Moniteurs et gestionnaires sur chaque nœud ------------------------------------------------
for n in "${NOEUDS[@]}"; do
  if sur "$n" "test -d /var/lib/ceph/mon/ceph-$n"; then
    echo "== $n : MON présent"
  else
    sur "$n" 'pveceph mon create'
  fi
  if sur "$n" "test -d /var/lib/ceph/mgr/ceph-$n"; then
    echo "== $n : MGR présent"
  else
    sur "$n" 'pveceph mgr create'
  fi
done

# --- 3. Mémoire des OSD : AVANT leur création, dans la base de configuration ---------------------
ceph config set osd osd_memory_target "$MEMOIRE_OSD"

# --- 4. OSD : deux par nœud, disques contrôlés --------------------------------------------------
for n in "${NOEUDS[@]}"; do
  for s in "${SERIES_OSD[@]}"; do
    d="scsi-0QEMU_QEMU_HARDDISK_$n-$s"
    chemin="/dev/disk/by-id/$d"
    # Déjà un OSD sur ce disque ? (ceph-volume connaît le périphérique sous son vrai nom)
    if sur "$n" "ceph-volume lvm list \"\$(readlink -f $chemin)\" >/dev/null 2>&1"; then
      echo "== $n : $d porte déjà un OSD"
      continue
    fi
    # Taille exacte, aucune partition, aucune signature, aucun utilisateur.
    if ! sur "$n" "test -b $chemin \
        && [ \"\$(blockdev --getsize64 $chemin)\" = $TAILLE_OSD_OCTETS ] \
        && [ \"\$(lsblk -nro NAME $chemin | wc -l)\" = 1 ] \
        && [ -z \"\$(wipefs -n $chemin)\" ]"; then
      echo "$n : $d absent, de mauvaise taille, partitionné ou porteur d'une signature : REFUSÉ" >&2
      exit 1
    fi
    sur "$n" "pveceph osd create $chemin"
  done
done

# --- 5. Pool et stockage Proxmox ----------------------------------------------------------------
if ceph osd pool ls | grep -qx "$POOL"; then
  echo "== pool $POOL présent"
else
  pveceph pool create "$POOL" --size 3 --min_size 2 --pg_autoscale_mode on --application rbd --add_storages 1
fi

# --- 6. État final -------------------------------------------------------------------------------
ceph -s
ceph osd df tree
ceph osd pool get "$POOL" all | grep -E '^(size|min_size|pg_autoscale_mode):'
ceph config get osd osd_memory_target
pvesm status --storage "$POOL"
