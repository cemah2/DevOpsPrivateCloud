#!/usr/bin/env bash
# pbs01/pbs-identite.sh — espace de noms par1/identite et droits du jeton de pve01 (M24-E25).
# À lancer UNE fois sur pbs01, en root (modèle : pbs-jetons-socle.sh, M06-E28). Idempotent.
# Le jeton utilisé par le stockage Proxmox « pbs-par2 » (M00-E22) est réutilisé par
# « pbs-par2-identite » : il lui faut DatastoreBackup sur le nouvel espace de noms (il l'a déjà s'il
# l'a sur par1 : les droits sont hérités ; le script le vérifie et ne l'ajoute que s'il manque).
set -Eeuo pipefail

STORE="${STORE:-ds-lab}"
NS="${NS:-par1/identite}"
JETON="${JETON:-wb-backup@pbs!pve01}"

[[ $EUID -eq 0 ]] || { echo "à lancer en root sur pbs01" >&2; exit 1; }

if proxmox-backup-client namespace list --repository "root@pam@localhost:$STORE" 2>/dev/null | grep -qx "$NS"; then
  echo "espace de noms $NS : déjà présent"
else
  proxmox-backup-client namespace create "$NS" --repository "root@pam@localhost:$STORE"
  echo "espace de noms $NS : créé"
fi

if proxmox-backup-manager user permissions "$JETON" --path "/datastore/$STORE/$NS" 2>/dev/null | grep -q 'Datastore.Backup'; then
  echo "$JETON : Datastore.Backup sur $NS (hérité ou direct)"
else
  proxmox-backup-manager acl update "/datastore/$STORE/$NS" DatastoreBackup --auth-id "$JETON"
  echo "$JETON : DatastoreBackup accordé sur $NS"
fi
