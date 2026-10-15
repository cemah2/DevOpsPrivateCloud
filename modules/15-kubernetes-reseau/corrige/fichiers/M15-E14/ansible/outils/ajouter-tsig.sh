#!/usr/bin/env bash
# outils/ajouter-tsig.sh — plateforme/ansible (M15-E14). Génère le secret d'une clé TSIG hmac-sha256
# (32 octets aléatoires, base64) et l'ajoute (ou le REMPLACE : rotation) dans le fichier CHIFFRÉ
# inventories/lab/group_vars/role_dns/vault-lab.yml, sans fichier en clair, sans écran, sans ligne
# de commande visible dans ps (printf est une commande interne de bash). Même méthode que
# outils/ajouter-cle-ceph.sh (M08-E10).
# Usage (depuis la racine de ~/src/ansible) : outils/ajouter-tsig.sh certmanager-k8s
# Variable produite : vault_powerdns_tsig_<nom, tirets → soulignés> (ex. vault_powerdns_tsig_certmanager_k8s).
# Ensuite : inscrire la clé au registre des secrets, MR, pipeline (rôle powerdns_auth), puis
# recréer le Secret Kubernetes (plateforme/k8s : outils/secret-tsig.sh).
set -euo pipefail
umask 077

NOM="${1:?Usage : $0 <nom-de-clé-tsig>}"
[[ "$NOM" =~ ^[a-z0-9-]+$ ]] || { echo "nom de clé invalide : minuscules, chiffres, tirets" >&2; exit 2; }
FICHIER=inventories/lab/group_vars/role_dns/vault-lab.yml
VAR="vault_powerdns_tsig_${NOM//-/_}"
VAULT=(uv run ansible-vault)

[[ -f ansible.cfg && -d inventories/lab ]] || { echo "à lancer depuis la racine de plateforme/ansible" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

secret="$(openssl rand -base64 32)"
{
  if [[ -f "$FICHIER" ]]; then "${VAULT[@]}" view "$FICHIER" | grep -v "^${VAR}:"; else echo "---"; fi
  printf '%s: "%s"\n' "$VAR" "$secret"
} | "${VAULT[@]}" encrypt --encrypt-vault-id lab --output "$tmp/vault-lab.yml" -
unset secret
mv -f "$tmp/vault-lab.yml" "$FICHIER"
echo "$VAR écrite dans $FICHIER (chiffré, identité lab). Inscris la clé TSIG $NOM au registre des secrets."
