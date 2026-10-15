#!/usr/bin/env bash
# outils/secret-tsig.sh — plateforme/k8s (M15-E14, réutilisé en E15 et E23).
# (Re)crée le Secret Kubernetes d'une clé TSIG à partir du Vault de plateforme/ansible, sans fichier
# en clair ni argument visible dans ps : le secret ne passe que par une variable d'environnement de
# yq et par le tube vers kubectl.
# Usage : outils/secret-tsig.sh <clé> <espace> <secret>
#   outils/secret-tsig.sh certmanager-k8s cert-manager tsig-certmanager-k8s
#   outils/secret-tsig.sh externaldns-k8s external-dns tsig-externaldns-k8s
# Le Secret porte la clé « secret » (lue par le ClusterIssuer et par ExternalDNS).
# Prérequis : clone de plateforme/ansible (WB_SRC/ansible), uv + ansible-vault (identité lab),
#             yq (mikefarah) 4.x, kubectl avec ton identité d'administration.
set -euo pipefail
umask 077

NOM="${1:?Usage : $0 <clé> <espace> <secret>}"
ESPACE="${2:?espace manquant}"
SECRET="${3:?nom du Secret manquant}"
[[ "$NOM" =~ ^[a-z0-9-]+$ && "$ESPACE" =~ ^[a-z0-9-]+$ && "$SECRET" =~ ^[a-z0-9-]+$ ]] \
  || { echo "noms invalides" >&2; exit 2; }
ANSIBLE_DIR="${WB_SRC:-$HOME/src}/ansible"
VAULT_FICHIER=inventories/lab/group_vars/role_dns/vault-lab.yml
VAR="vault_powerdns_tsig_${NOM//-/_}"

valeur="$(cd "$ANSIBLE_DIR" && uv run ansible-vault view "$VAULT_FICHIER" | V="$VAR" yq -r '.[strenv(V)] // ""')"
# hmac-sha256 : 32 octets → 44 caractères base64 terminés par « = ».
[[ "$valeur" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "$VAR absente du Vault ou mal formée" >&2; exit 1; }

kubectl get namespace "$ESPACE" >/dev/null

TSIG="$valeur" N="$SECRET" E="$ESPACE" K="$NOM" yq -n '
  .apiVersion = "v1" | .kind = "Secret" | .type = "Opaque"
  | .metadata.name = strenv(N) | .metadata.namespace = strenv(E)
  | .metadata.labels."app.kubernetes.io/part-of" = "reseau-k8s-par1"
  | .metadata.annotations."medisphere.internal/source" = "plateforme/ansible vault-lab (outils/secret-tsig.sh)"
  | .metadata.annotations."medisphere.internal/cle-tsig" = strenv(K)
  | .stringData.secret = strenv(TSIG)' \
  | kubectl apply --server-side --force-conflicts --field-manager=secret-tsig -f -
unset valeur
echo "Secret $ESPACE/$SECRET à jour (clé TSIG $NOM)."
