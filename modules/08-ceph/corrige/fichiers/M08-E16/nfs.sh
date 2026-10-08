#!/usr/bin/env bash
# nfs.sh — M08-E16 (PLAT-926) : cluster NFS « par1 », sous-volume et export /legacy-rdv restreint
# à cephcli01 avec root_squash. Depuis adm01. Idempotent.
# shellcheck disable=SC2029  # développement local voulu dans les commandes ssh
set -euo pipefail

ADMIN=${WB_CEPH_ADMIN:-ceph01}
c() { ssh -o BatchMode=yes "$ADMIN" "sudo ceph $(printf '%q ' "$@")" 2>/dev/null; }

c orch host label add ceph01 nfs >/dev/null
c fs subvolume create cephfs legacy-rdv --group_name applications --size 5368709120
CHEMIN="$(c fs subvolume getpath cephfs legacy-rdv --group_name applications | tr -d '\r')"

c nfs cluster ls | grep -qw par1 || c nfs cluster create par1 "label:nfs count:1"
c nfs cluster info par1

if ! c nfs export ls par1 | grep -q '"/legacy-rdv"'; then
  c nfs export create cephfs --cluster-id par1 --pseudo-path /legacy-rdv --fsname cephfs \
    --path "$CHEMIN" --client_addr 10.10.30.20 --squash root_squash
fi
c nfs export info par1 /legacy-rdv

cat <<FIN

Sur cephcli01 :
  sudo apt-get install -y nfs-common && sudo mkdir -p /mnt/legacy-rdv
  sudo mount -t nfs -o vers=4.2 10.10.30.51:/legacy-rdv /mnt/legacy-rdv
Dossier de l'application (côté CephFS, sans squash) : monter le sous-volume avec un client CephFS
autorisé (ex. « ceph fs subvolume authorize cephfs legacy-rdv admin-legacy --group_name applications »,
clé temporaire supprimée ensuite), puis mkdir pieces-jointes && chown 1000:1000 pieces-jointes.
Modifier l'export : ceph nfs export info par1 /legacy-rdv > export.json ; éditer ; ceph nfs export apply par1 -i export.json
FIN
