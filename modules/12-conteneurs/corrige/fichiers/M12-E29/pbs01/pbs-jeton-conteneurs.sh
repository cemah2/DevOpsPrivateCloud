#!/usr/bin/env bash
# pbs01 : espace de noms par1/conteneurs et jeton limité pour ctr01 (M12-E29, PLAT-1355).
# Même méthode que pbs-jetons-socle.sh (M06-E28) : le jeton n'a que DatastoreBackup sur son espace
# (droits du jeton = intersection avec ceux de wb-backup@pbs). À lancer en root sur pbs01.
# Retour arrière : proxmox-backup-manager user delete-token wb-backup@pbs ctr01 ; supprimer l'ACL ;
# supprimer l'espace de noms par1/conteneurs VIDE (proxmox-backup-client namespace delete …).
set -euo pipefail
DS=ds-lab
NS=par1/conteneurs
JETON=ctr01

# L'espace de noms se crée avec le client (API du datastore), en root@pam sur pbs01 lui-même.
if ! proxmox-backup-client namespace list --repository "root@pam@localhost:$DS" 2>/dev/null | grep -qx "$NS"; then
  proxmox-backup-client namespace create "$NS" --repository "root@pam@localhost:$DS"
fi
if ! proxmox-backup-manager user list-tokens wb-backup@pbs --output-format json | grep -q "\"token-name\": *\"$JETON\""; then
  echo "Secret du jeton (affiché UNE fois : directement dans Vault « critique ») :"
  proxmox-backup-manager user generate-token wb-backup@pbs "$JETON"
fi
proxmox-backup-manager acl update "/datastore/$DS/$NS" DatastoreBackup --auth-id "wb-backup@pbs!$JETON"
proxmox-backup-manager acl update "/datastore/$DS/$NS" DatastoreBackup --auth-id wb-backup@pbs
proxmox-backup-manager acl list --output-format text | grep -F "$NS"
