#!/usr/bin/env bash
# outils/ajouter-cle-ceph.sh — plateforme/ansible (M08-E10, réutilisé en E13 et E17).
# Ajoute (ou remplace) la clé d'un client cephx dans le fichier CHIFFRÉ
# inventories/lab/group_vars/role_ceph_client/vault-lab.yml, sans que la clé passe par un fichier
# en clair, l'écran ou une ligne de commande : nœud _admin → tube → ansible-vault → fichier chiffré.
# Usage (depuis la racine de ~/src/ansible) : outils/ajouter-cle-ceph.sh client.outillage
# Variable produite : vault_ceph_cle_<nom sans « client. », tirets → soulignés>.
# Ensuite : référencer la variable dans ceph_client.yml (ceph_client_cles), MR, pipeline.
set -euo pipefail
umask 077

CLIENT="${1:?Usage : $0 client.<nom>}"
[[ "$CLIENT" =~ ^client\.[a-z0-9-]+$ && "$CLIENT" != client.admin ]] || { echo "nom de client invalide (et jamais client.admin)" >&2; exit 2; }
ADMIN="${WB_CEPH_ADMIN:-ceph01}"
FICHIER=inventories/lab/group_vars/role_ceph_client/vault-lab.yml
VAR="vault_ceph_cle_$(sed 's/^client\.//; s/-/_/g' <<<"$CLIENT")"
VAULT=(uv run ansible-vault)

[[ -f ansible.cfg && -d inventories/lab ]] || { echo "à lancer depuis la racine de plateforme/ansible" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# La clé, lue sur le nœud _admin : elle n'existe que dans ce tube et dans la variable du shell.
# shellcheck disable=SC2029  # développement local voulu
cle="$(ssh -o BatchMode=yes "$ADMIN" "sudo ceph auth get-key $CLIENT")"
[[ "$cle" =~ ^AQ[A-Za-z0-9+/=]{38}$ ]] || { echo "clé cephx introuvable ou inattendue pour $CLIENT" >&2; exit 1; }

{
  if [[ -f "$FICHIER" ]]; then "${VAULT[@]}" view "$FICHIER" | grep -v "^${VAR}:"; else echo "---"; fi
  printf '%s: "%s"\n' "$VAR" "$cle"
} | "${VAULT[@]}" encrypt --encrypt-vault-id lab --output "$tmp/vault-lab.yml" -
unset cle
mv -f "$tmp/vault-lab.yml" "$FICHIER"
echo "$VAR ajoutée à $FICHIER (chiffré, identité lab). Inscris $CLIENT au registre des secrets."
