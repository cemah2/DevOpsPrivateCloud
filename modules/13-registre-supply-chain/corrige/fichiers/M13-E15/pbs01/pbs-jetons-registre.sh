#!/usr/bin/env bash
# pbs-jetons-registre.sh — à lancer en root sur pbs01 (M13-E15). Même modèle que pbs-jetons-socle.sh
# (M06-E28). Idempotent : ce qui existe n'est pas recréé. Les secrets des jetons sont affichés UNE
# SEULE FOIS : range-les aussitôt dans Vault « critique ».
#   - espace de noms par1/registre ;
#   - jeton wb-backup@pbs!reg01 : DatastoreBackup sur par1/registre (sauvegarde de reg01) ;
#   - jeton wb-restore@pbs!reg02 : DatastoreReader sur par1/registre (ESSAI de restauration sur reg02),
#     supprimé après l'essai. L'utilisateur wb-restore@pbs doit exister avec le même droit en lecture
#     (les droits d'un jeton sont l'intersection avec ceux de son utilisateur).
set -euo pipefail

DATASTORE=ds-lab
NS=par1/registre

[[ $EUID -eq 0 ]] || {
  echo "à lancer en root sur pbs01" >&2
  exit 1
}

if proxmox-backup-client namespace list --repository "root@pam@localhost:$DATASTORE" --ns par1 2>/dev/null \
  | grep -qw "$NS"; then
  echo "espace de noms $NS : existe"
else
  proxmox-backup-client namespace create "$NS" --repository "root@pam@localhost:$DATASTORE"
  echo "espace de noms $NS : créé"
fi

# jeton UTILISATEUR NOM RÔLE COMMENTAIRE
jeton() {
  local u="$1" n="$2" role="$3" c="$4"
  if proxmox-backup-manager user list-tokens "$u" --output-format json \
    | grep -q "\"tokenid\" *: *\"$u!$n\""; then
    echo "jeton $u!$n : existe (secret non réaffiché)"
  else
    echo "jeton $u!$n : création — NOTE LE SECRET CI-DESSOUS DANS VAULT, il ne sera plus affiché"
    proxmox-backup-manager user generate-token "$u" "$n" --comment "$c"
  fi
  proxmox-backup-manager acl update "/datastore/$DATASTORE/$NS" "$role" --auth-id "$u!$n"
}

jeton wb-backup@pbs reg01 DatastoreBackup "Sauvegarde applicative de Harbor (reg01, M13-E15)"

if ! proxmox-backup-manager user list --output-format json | grep -q '"userid" *: *"wb-restore@pbs"'; then
  proxmox-backup-manager user create wb-restore@pbs --comment "Essais de restauration (workbook, M13-E15)"
fi
proxmox-backup-manager acl update "/datastore/$DATASTORE/$NS" DatastoreReader --auth-id wb-restore@pbs
jeton wb-restore@pbs reg02 DatastoreReader "Essai de restauration de Harbor sur reg02 (M13-E15, temporaire)"

echo
echo "Contrôle des droits effectifs :"
proxmox-backup-manager user permissions 'wb-backup@pbs!reg01' --path "/datastore/$DATASTORE/$NS"
proxmox-backup-manager user permissions 'wb-restore@pbs!reg02' --path "/datastore/$DATASTORE/$NS"
echo "Après l'essai : proxmox-backup-manager user delete-token wb-restore@pbs reg02"
