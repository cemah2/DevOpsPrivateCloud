#!/usr/bin/env bash
# pbs-jetons-socle.sh — à lancer en root sur pbs01 (M06-E28).
# Crée, pour chaque hôte, l'espace de noms par1/<hôte> et un jeton wb-backup@pbs!<hôte> limité à
# cet espace (rôle DatastoreBackup), sur le modèle de M01-E28. Idempotent : ce qui existe n'est
# pas recréé. Les secrets des jetons sont affichés UNE SEULE FOIS : range-les aussitôt dans Vault.
set -euo pipefail

DATASTORE=ds-lab
HOTES=(dns01 ca01 nbx01)

[[ $EUID -eq 0 ]] || { echo "à lancer en root sur pbs01" >&2; exit 1; }

for h in "${HOTES[@]}"; do
  ns="par1/$h"
  if proxmox-backup-client namespace list --repository "root@pam@localhost:$DATASTORE" --ns par1 2>/dev/null \
       | grep -qw "$ns"; then
    echo "espace de noms $ns : existe"
  else
    proxmox-backup-client namespace create "$ns" --repository "root@pam@localhost:$DATASTORE"
    echo "espace de noms $ns : créé"
  fi

  if proxmox-backup-manager user list-tokens wb-backup@pbs --output-format json \
       | grep -q "\"tokenid\" *: *\"wb-backup@pbs!$h\""; then
    echo "jeton wb-backup@pbs!$h : existe (secret non réaffiché)"
  else
    echo "jeton wb-backup@pbs!$h : création — NOTE LE SECRET CI-DESSOUS DANS VAULT, il ne sera plus affiché"
    proxmox-backup-manager user generate-token wb-backup@pbs "$h" --comment "Sauvegarde applicative de $h (M06-E28)"
  fi

  # Droits du jeton = intersection avec ceux de wb-backup@pbs (DatastoreBackup sur par1, M00-E22) :
  # ce jeton ne voit que par1/<hôte>, ne lit ni ne purge les sauvegardes des autres.
  proxmox-backup-manager acl update "/datastore/$DATASTORE/$ns" DatastoreBackup --auth-id "wb-backup@pbs!$h"
done

echo
echo "Contrôle des droits effectifs :"
for h in "${HOTES[@]}"; do
  proxmox-backup-manager user permissions "wb-backup@pbs!$h" --path "/datastore/$DATASTORE/par1/$h"
done
echo "Vérifie que la tâche de purge de par1 descend dans les sous-espaces (max-depth) : proxmox-backup-manager prune-job list"
