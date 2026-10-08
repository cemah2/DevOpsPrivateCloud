#!/usr/bin/env bash
# pbs-jeton-openstack.sh — à lancer en root sur pbs01 (M10-E25).
# Crée l'espace de noms par1/openstack et le jeton wb-backup@pbs!osctl01 limité à cet espace
# (rôle DatastoreBackup), sur le modèle de pbs-jetons-socle.sh (M06-E28). Idempotent.
# Le secret du jeton est affiché UNE SEULE FOIS : range-le aussitôt dans Vault (critique).
set -euo pipefail

DATASTORE=ds-lab
NS=par1/openstack
JETON=osctl01

[[ $EUID -eq 0 ]] || { echo "à lancer en root sur pbs01" >&2; exit 1; }

if proxmox-backup-client namespace list --repository "root@pam@localhost:$DATASTORE" --ns par1 2>/dev/null \
     | grep -qw "$NS"; then
  echo "espace de noms $NS : existe"
else
  proxmox-backup-client namespace create "$NS" --repository "root@pam@localhost:$DATASTORE"
  echo "espace de noms $NS : créé"
fi

if proxmox-backup-manager user list-tokens wb-backup@pbs --output-format json \
     | grep -q "\"tokenid\" *: *\"wb-backup@pbs!$JETON\""; then
  echo "jeton wb-backup@pbs!$JETON : existe (secret non réaffiché)"
else
  echo "jeton wb-backup@pbs!$JETON : création — NOTE LE SECRET CI-DESSOUS DANS VAULT, il ne sera plus affiché"
  proxmox-backup-manager user generate-token wb-backup@pbs "$JETON" --comment "Base OpenStack depuis osctl01 (M10-E25)"
fi

# Droits effectifs = intersection avec ceux de wb-backup@pbs (DatastoreBackup sur par1, M00-E22).
proxmox-backup-manager acl update "/datastore/$DATASTORE/$NS" DatastoreBackup --auth-id "wb-backup@pbs!$JETON"

echo
echo "Droits effectifs :"
proxmox-backup-manager user permissions "wb-backup@pbs!$JETON" --path "/datastore/$DATASTORE/$NS"
echo "Contrôle : le jeton ne doit RIEN voir dans par1/dns01 :"
proxmox-backup-manager user permissions "wb-backup@pbs!$JETON" --path "/datastore/$DATASTORE/par1/dns01"
