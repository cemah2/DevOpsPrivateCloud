#!/usr/bin/env bash
# pbs-jeton-ceph.sh — à lancer en root sur pbs01 (M08-E25).
# Crée l'espace de noms par1/ceph et le jeton wb-backup@pbs!cephcli01 limité à cet espace (rôle
# DatastoreBackup), sur le modèle de pbs-jetons-socle.sh (M06-E28). Idempotent. Le secret du jeton
# est affiché UNE SEULE FOIS : range-le aussitôt dans Vault (vault_pbs_jeton_cephcli01).
set -euo pipefail

DATASTORE=ds-lab
NS=par1/ceph
HOTE=cephcli01

[[ $EUID -eq 0 ]] || { echo "à lancer en root sur pbs01" >&2; exit 1; }

if proxmox-backup-client namespace list --repository "root@pam@localhost:$DATASTORE" --ns par1 2>/dev/null \
     | grep -qw "$NS"; then
  echo "espace de noms $NS : existe"
else
  proxmox-backup-client namespace create "$NS" --repository "root@pam@localhost:$DATASTORE"
  echo "espace de noms $NS : créé"
fi

if proxmox-backup-manager user list-tokens wb-backup@pbs --output-format json \
     | grep -q "\"tokenid\" *: *\"wb-backup@pbs!$HOTE\""; then
  echo "jeton wb-backup@pbs!$HOTE : existe (secret non réaffiché)"
else
  echo "jeton wb-backup@pbs!$HOTE : création — NOTE LE SECRET CI-DESSOUS DANS VAULT, il ne sera plus affiché"
  proxmox-backup-manager user generate-token wb-backup@pbs "$HOTE" --comment "Sauvegarde de ceph-par1 (M08-E25)"
fi

# Droits du jeton = intersection avec ceux de wb-backup@pbs : ce jeton ne voit que par1/ceph.
proxmox-backup-manager acl update "/datastore/$DATASTORE/$NS" DatastoreBackup --auth-id "wb-backup@pbs!$HOTE"

echo
echo "Contrôle des droits effectifs :"
proxmox-backup-manager user permissions "wb-backup@pbs!$HOTE" --path "/datastore/$DATASTORE/$NS"
echo "Vérifie que la tâche de purge de par1 descend dans par1/ceph (max-depth) et garde au moins 14 jours"
echo "(chaîne complet + incrémentaux) : proxmox-backup-manager prune-job list"
