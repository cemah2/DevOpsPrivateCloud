#!/usr/bin/env bash
# plateforme/k8s — outils/secret-rbd-chiffre.sh (M16-E26, SEC-1726)
# Crée ou met à jour le Secret csi-rbd-secret-chiffre (espace ceph-csi) de la classe
# ceph-rbd-chiffre : identité cephx de client.k8s (userID, userKey) et KEK (encryptionPassphrase).
# Voisin de outils/ceph-csi-secrets.sh (E06-E07), même source et mêmes conventions : le fichier
# Ansible Vault « critique » secrets/ceph-csi.yml, qui contient désormais
#   ceph_csi_rbd_cle      <clé cephx de client.k8s>             (E06)
#   ceph_csi_cephfs_cle   <clé cephx de client.k8s-cephfs>      (E07)
#   ceph_csi_rbd_kek      <KEK, 48 octets aléatoires en base64>  (E26)
# Les secrets ne passent ni par un argument de commande, ni par un fichier en clair : déchiffrés sur
# la sortie standard, transformés par yq/jq, envoyés à kubectl apply -f - .
# Usage, sur adm01, depuis la racine de plateforme/k8s :
#   outils/secret-rbd-chiffre.sh [--verifier]
# Variables : MS_ANSIBLE_DIR (défaut ~/src/ansible), MS_VAULT_ID (défaut critique@…/vault-pass-client.sh).
# Ne jamais lancer avec « bash -x » : la trace afficherait les clés.
set -Eeuo pipefail
umask 077

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FICHIER="${CEPH_CSI_VAULT_FICHIER:-$RACINE/secrets/ceph-csi.yml}"
ANSIBLE_DIR="${MS_ANSIBLE_DIR:-$HOME/src/ansible}"
VAULT_ID="${MS_VAULT_ID:-critique@$ANSIBLE_DIR/outils/vault-pass-client.sh}"
UTILISATEUR=k8s          # client.k8s, sans le préfixe « client. » (comme csi-rbd-secret)

[[ -r "$FICHIER" ]] || { echo "fichier Vault illisible : $FICHIER" >&2; exit 2; }

dechiffrer() { (cd "$ANSIBLE_DIR" && uv run ansible-vault view --vault-id "$VAULT_ID" "$FICHIER"); }

if [[ "${1:-}" == --verifier ]]; then
  # Contrôle sans rien afficher : la clé et la KEK existent, et la KEK fait au moins 32 octets.
  if dechiffrer | yq -o json | jq -e '
      ((.ceph_csi_rbd_cle // "") | length > 0)
      and (((.ceph_csi_rbd_kek // "") | @base64d | length) >= 32)' >/dev/null; then
    echo "coffre complet (clé de client.k8s et KEK présentes)"
    exit 0
  fi
  echo "coffre incomplet : $FICHIER (ceph_csi_rbd_cle ou ceph_csi_rbd_kek)" >&2
  exit 1
fi

dechiffrer | yq -o json | jq --arg u "$UTILISATEUR" '{
    apiVersion: "v1", kind: "Secret", type: "Opaque",
    metadata: {name: "csi-rbd-secret-chiffre", namespace: "ceph-csi",
               labels: {"app.kubernetes.io/managed-by": "plateforme-k8s-outils"}},
    stringData: {userID: $u, userKey: .ceph_csi_rbd_cle,
                 encryptionPassphrase: .ceph_csi_rbd_kek}
  }' | kubectl apply --server-side --field-manager=secret-rbd-chiffre -f - >/dev/null
echo "Secret ceph-csi/csi-rbd-secret-chiffre à jour (aucune valeur affichée)"
