#!/usr/bin/env bash
# plateforme/k8s — outils/secret-rbd-chiffre.sh (M16-E26, SEC-1726)
# Crée ou met à jour le Secret csi-rbd-secret-chiffre (espace ceph-csi) de la classe
# ceph-rbd-chiffre : identité cephx de client.k8s (userID, userKey) et KEK (encryptionPassphrase).
# Les valeurs viennent du fichier Ansible Vault « critique » secrets/ceph-csi.vault.yml (le même que
# pour csi-rbd-secret en E06 ; adapte le chemin et les noms de variables aux tiens) :
#   ceph_csi_rbd_utilisateur   k8s           (sans le préfixe « client. »)
#   ceph_csi_rbd_cle           <clé cephx>
#   ceph_csi_rbd_kek           <KEK, 48 octets aléatoires en base64>
# Les secrets ne passent ni par un argument de commande, ni par un fichier en clair : déchiffrés sur
# la sortie standard, transformés par yq/jq, envoyés à kubectl apply -f - .
# Usage : outils/secret-rbd-chiffre.sh [--verifier]
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."
coffre=secrets/ceph-csi.vault.yml
ident="critique@$HOME/src/ansible/outils/vault-pass-client.sh"

dechiffrer() { uv run --project "$HOME/src/ansible" ansible-vault view --vault-id "$ident" "$coffre"; }

if [[ "${1:-}" == --verifier ]]; then
  # Contrôle sans rien afficher : les trois variables existent et la KEK fait au moins 32 octets.
  if dechiffrer | yq -o json | jq -e '
      (.ceph_csi_rbd_utilisateur | length > 0) and (.ceph_csi_rbd_cle | length > 0)
      and ((.ceph_csi_rbd_kek | @base64d | length) >= 32)' >/dev/null; then
    echo "coffre complet (identité et KEK présentes)"
    exit 0
  fi
  echo "coffre incomplet : $coffre" >&2
  exit 1
fi

dechiffrer | yq -o json | jq '{
    apiVersion: "v1", kind: "Secret", type: "Opaque",
    metadata: {name: "csi-rbd-secret-chiffre", namespace: "ceph-csi",
               labels: {"app.kubernetes.io/managed-by": "plateforme-k8s-outils"}},
    stringData: {userID: .ceph_csi_rbd_utilisateur, userKey: .ceph_csi_rbd_cle,
                 encryptionPassphrase: .ceph_csi_rbd_kek}
  }' | kubectl apply --server-side --field-manager=secret-rbd-chiffre -f -
