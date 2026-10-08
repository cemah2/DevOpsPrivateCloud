#!/usr/bin/env bash
# pbs01-hv.sh — namespace, compte, jeton et ACL de hv-par1 sur pbs01 (M09-E15). Rejouable.
#
# ⚠️ À lancer en root sur pbs01, APRÈS avoir relevé l'état (voir la fin du fichier : --etat).
# Ne touche ni à wb-backup@pbs, ni au namespace par1, ni aux tâches existantes.
# Le secret du jeton n'est affiché qu'à sa création : copie-le aussitôt (saisi ensuite sans écho
# sur hv01, voir pbs-stockage.sh) ; il n'est écrit nulle part par ce script.
#
#   ./pbs01-hv.sh --etat       relevé de l'état (à conserver dans ~/m09/e15/ sur adm01)
#   ./pbs01-hv.sh              création / remise en conformité
#   ./pbs01-hv.sh --annuler    retour arrière (jeton, ACL, utilisateur, namespace s'il est VIDE)
set -euo pipefail

STORE=ds-lab
NS=par1/hv
UTILISATEUR="wb-hv@pbs"
JETON=hv-par1
CHEMIN="/datastore/$STORE/$NS"
DEPOT="root@pam@localhost:$STORE"

etat() {
  echo "== utilisateurs";  proxmox-backup-manager user list --output-format text
  echo "== ACL";           proxmox-backup-manager acl list --output-format text
  echo "== namespaces";    proxmox-backup-client namespace list --repository "$DEPOT" --max-depth 3
  echo "== élagage";       proxmox-backup-manager prune-job list --output-format text
  echo "== vérification";  proxmox-backup-manager verify-job list --output-format text
}

annuler() {
  proxmox-backup-manager user delete-token "$UTILISATEUR" "$JETON" 2>/dev/null || true
  proxmox-backup-manager acl update "$CHEMIN" DatastoreBackup --auth-id "$UTILISATEUR!$JETON" --delete true 2>/dev/null || true
  proxmox-backup-manager acl update "$CHEMIN" DatastoreBackup --auth-id "$UTILISATEUR" --delete true 2>/dev/null || true
  proxmox-backup-manager user remove "$UTILISATEUR" 2>/dev/null || true
  # Un namespace qui contient des sauvegardes n'est PAS supprimé : décision humaine.
  proxmox-backup-client namespace delete "$NS" --repository "$DEPOT" \
    || echo "namespace $NS non supprimé (non vide ?) : à traiter à la main" >&2
}

case "${1:-}" in
  --etat) etat; exit 0 ;;
  --annuler) annuler; exit 0 ;;
  "") ;;
  *) echo "Usage : $0 [--etat|--annuler]" >&2; exit 2 ;;
esac

# --- Namespace (le parent par1 existe depuis M00-E22) ------------------------------------------------
# (sortie JSON : une liste d'objets {"ns": "…"} ; le format texte varie selon les versions)
if proxmox-backup-client namespace list --repository "$DEPOT" --max-depth 2 --output-format json \
    | grep -q "\"ns\": *\"$NS\""; then
  echo "== namespace $NS présent"
else
  proxmox-backup-client namespace create "$NS" --repository "$DEPOT"
fi

# --- Utilisateur et jeton -------------------------------------------------------------------------
if proxmox-backup-manager user list --output-format json | grep -q "\"$UTILISATEUR\""; then
  echo "== utilisateur $UTILISATEUR présent"
else
  proxmox-backup-manager user create "$UTILISATEUR" --comment "Sauvegardes du cluster hv-par1 (PLAT-1025)"
fi
if proxmox-backup-manager user list-tokens "$UTILISATEUR" --output-format json | grep -q "\"$UTILISATEUR!$JETON\""; then
  echo "== jeton $UTILISATEUR!$JETON présent (secret non réaffichable)"
else
  echo ">>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT (il ne sera plus affiché)."
  proxmox-backup-manager user generate-token "$UTILISATEUR" "$JETON" --comment "Stockage pbs-par2 de hv-par1"
fi

# --- ACL : l'utilisateur ET le jeton (droits du jeton = intersection), au plus près : le namespace --
proxmox-backup-manager acl update "$CHEMIN" DatastoreBackup --auth-id "$UTILISATEUR"
proxmox-backup-manager acl update "$CHEMIN" DatastoreBackup --auth-id "$UTILISATEUR!$JETON"

echo "== droits effectifs du jeton"
proxmox-backup-manager user permissions "$UTILISATEUR!$JETON" --path "$CHEMIN"
proxmox-backup-manager user permissions "$UTILISATEUR!$JETON" --path "/datastore/$STORE/par1"

echo "== empreinte du certificat (à épingler côté hv-par1)"
proxmox-backup-manager cert info | grep -i fingerprint
