#!/usr/bin/env bash
# rgw-compartiment.sh — utilisateur RGW dédié, quota et compartiment d'un locataire (F2-S08, PLAT-3208).
# Généralise thanos-rgw.sh (M21-E24). Rangé dans plateforme/ceph (outils/), décrit par
# outils/rgw-compartiments.yaml, lancé depuis adm01 par une personne de plateforme-admins (connectée à
# OpenBao par OIDC) ; idempotent : relancé, il ne recrée ni l'utilisateur ni ses clés, il réapplique le
# quota et vérifie le compartiment.
#
# Usage : rgw-compartiment.sh UTILISATEUR COMPARTIMENT QUOTA CHEMIN_KV
#   ex.   rgw-compartiment.sh data-resultats data-resultats 5G data/traitements/s3-resultats
#
# - Utilisateur RGW « classique » (pas un compte IAM) : un locataire, un compartiment (--max-buckets 1).
# - Les clés ne s'affichent jamais : elles passent de ceph01 à OpenBao par des tubes (kv/<CHEMIN_KV>,
#   clés AWS_ACCESS_KEY_ID et AWS_SECRET_ACCESS_KEY), d'où ESO les sert à l'espace du locataire.
# - Codes retour : 0 succès, 1 erreur, 2 usage.
set -euo pipefail

usage() { echo "Usage : $0 UTILISATEUR COMPARTIMENT QUOTA CHEMIN_KV   (ex. data-resultats data-resultats 5G data/traitements/s3-resultats)" >&2; exit 2; }
(($# == 4)) || usage
UTILISATEUR="$1" COMPARTIMENT="$2" QUOTA="$3" CHEMIN_KV="$4"
[[ "$UTILISATEUR" =~ ^[a-z][a-z0-9-]{2,40}$ && "$COMPARTIMENT" =~ ^[a-z][a-z0-9-]{2,62}$ ]] || usage
[[ "$QUOTA" =~ ^[0-9]+[KMGT]$ ]] || usage
[[ "$CHEMIN_KV" =~ ^[a-z0-9-]+(/[a-z0-9-]+)+$ ]] || usage

CEPH_ADMIN="${WB_CEPH_ADMIN:-ceph01}"
RGW_URL="${RGW_URL:-https://rgw.par1.medisphere.internal}"
export BAO_ADDR="${BAO_ADDR:-https://openbao.par1.medisphere.internal:8200}"

for c in ssh jq aws bao; do
  command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; exit 1; }
done
bao token lookup >/dev/null 2>&1 || { echo "pas de jeton OpenBao valide : bao login -method=oidc" >&2; exit 1; }

rgw() { ssh -o BatchMode=yes "$CEPH_ADMIN" sudo -n radosgw-admin "$@"; }

# 1. Utilisateur, créé une seule fois ; clés envoyées directement à OpenBao (JSON sur l'entrée standard).
if rgw user info --uid="$UTILISATEUR" >/dev/null 2>&1; then
  echo "utilisateur RGW $UTILISATEUR : existe déjà (clés inchangées)"
else
  rgw user create --uid="$UTILISATEUR" --display-name="Locataire : $UTILISATEUR (PLAT-3208)" --max-buckets=1 |
    jq -e '{AWS_ACCESS_KEY_ID: .keys[0].access_key, AWS_SECRET_ACCESS_KEY: .keys[0].secret_key}
           | select(.AWS_SECRET_ACCESS_KEY != null)' |
    bao kv put "kv/$CHEMIN_KV" - >/dev/null
  echo "utilisateur RGW $UTILISATEUR créé ; clés rangées dans kv/$CHEMIN_KV"
fi

# 2. Quota de l'utilisateur (statistiques asynchrones : léger dépassement possible).
rgw quota set --quota-scope=user --uid="$UTILISATEUR" --max-size="$QUOTA"
rgw quota enable --quota-scope=user --uid="$UTILISATEUR"

# 3. Compartiment, créé PAR l'utilisateur (il en est propriétaire), avec ses propres clés lues dans
#    OpenBao le temps de la commande (environnement d'un sous-shell, jamais sur la ligne de commande).
(
  eval "$(bao kv get -format=json "kv/$CHEMIN_KV" |
    jq -r '.data.data | "export AWS_ACCESS_KEY_ID=\(.AWS_ACCESS_KEY_ID | @sh) AWS_SECRET_ACCESS_KEY=\(.AWS_SECRET_ACCESS_KEY | @sh)"')"
  export AWS_ENDPOINT_URL="$RGW_URL" AWS_DEFAULT_REGION=us-east-1 AWS_REQUEST_CHECKSUM_CALCULATION=when_required
  if aws s3api head-bucket --bucket "$COMPARTIMENT" >/dev/null 2>&1; then
    echo "compartiment $COMPARTIMENT : existe déjà"
  else
    aws s3api create-bucket --bucket "$COMPARTIMENT" >/dev/null
    echo "compartiment $COMPARTIMENT créé"
  fi
  # Résultats : conservés 400 jours (comparaison d'une année sur l'autre), puis effacés.
  aws s3api put-bucket-lifecycle-configuration --bucket "$COMPARTIMENT" --lifecycle-configuration \
    '{"Rules":[{"ID":"conservation-400-jours","Status":"Enabled","Filter":{"Prefix":""},"Expiration":{"Days":400}}]}'
  aws s3api list-objects-v2 --bucket "$COMPARTIMENT" --max-items 1 >/dev/null
  if aws s3api create-bucket --bucket "${COMPARTIMENT}-essai" >/dev/null 2>&1; then
    aws s3api delete-bucket --bucket "${COMPARTIMENT}-essai" >/dev/null 2>&1 || true
    echo "ATTENTION : un second compartiment a pu être créé (--max-buckets non appliqué ?)" >&2
    exit 1
  fi
  echo "contrôles : liste autorisée, second compartiment refusé"
)

# 4. État, sans secret.
rgw user info --uid="$UTILISATEUR" | jq '{user_id, max_buckets, user_quota}'
