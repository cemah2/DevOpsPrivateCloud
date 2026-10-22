#!/usr/bin/env bash
# thanos-rgw.sh — utilisateur RGW « thanos », quota et compartiment thanos-k8s-par1 (M21-E24, PLAT-2224).
# À lancer depuis adm01 (rangé dans plateforme/ceph, outils/). Idempotent : relancé, il ne recrée ni
# l'utilisateur ni ses clés, il réapplique le quota et vérifie le compartiment.
#
# Choix (voir le corrigé) : utilisateur RGW « classique » (pas un compte IAM du M08-E12) : un seul
# composant, un seul compartiment, aucune politique fine à déléguer. Il ne peut posséder qu'UN
# compartiment (--max-buckets 1) et son quota borne ce que Thanos peut écrire dans ceph-par1.
#
# La clé secrète ne s'affiche jamais : elle passe de ceph01 à adm01 par le tube SSH, puis dans un
# fichier 600. À toi ensuite de la chiffrer dans le Vault « critique » (plateforme/k8s,
# secrets/thanos.yml) et de l'inscrire au registre des secrets.
set -euo pipefail

CEPH_ADMIN="${WB_CEPH_ADMIN:-ceph01}"
UTILISATEUR=thanos
COMPARTIMENT=thanos-k8s-par1
QUOTA="${QUOTA_THANOS:-40G}"
ENV_FICHIER="${HOME}/.config/workbook/s3-thanos.env"
RGW_URL=https://rgw.par1.medisphere.internal

rgw() { ssh -o BatchMode=yes "$CEPH_ADMIN" sudo -n radosgw-admin "$@"; }

install -d -m 700 "$(dirname "$ENV_FICHIER")"

# 1. Utilisateur (créé une seule fois).
if rgw user info --uid="$UTILISATEUR" >/dev/null 2>&1; then
  echo "utilisateur RGW $UTILISATEUR : existe déjà (clés inchangées)"
else
  umask 077
  tmp="$(mktemp -p "$(dirname "$ENV_FICHIER")")"
  trap 'rm -f "$tmp"' EXIT
  rgw user create --uid="$UTILISATEUR" --display-name="Thanos (k8s-par1, supervision)" \
      --max-buckets=1 \
    | jq -r '.keys[0] | "AWS_ACCESS_KEY_ID=\(.access_key)\nAWS_SECRET_ACCESS_KEY=\(.secret_key)"' > "$tmp"
  {
    echo "AWS_ENDPOINT_URL=$RGW_URL"
    echo "AWS_DEFAULT_REGION=us-east-1"
    echo "AWS_REQUEST_CHECKSUM_CALCULATION=when_required"
  } >> "$tmp"
  grep -q '^AWS_SECRET_ACCESS_KEY=.' "$tmp" || { echo "clés introuvables dans la sortie de radosgw-admin" >&2; exit 1; }
  mv "$tmp" "$ENV_FICHIER"
  trap - EXIT
  chmod 600 "$ENV_FICHIER"
  echo "utilisateur RGW $UTILISATEUR créé ; identifiants dans $ENV_FICHIER (600)"
fi

# 2. Quota de l'utilisateur (taille totale de ses objets). Statistiques asynchrones : le dépassement
#    peut être léger. Au-delà, PutObject répond QuotaExceeded : les sidecars n'envoient plus.
rgw quota set --quota-scope=user --uid="$UTILISATEUR" --max-size="$QUOTA"
rgw quota enable --quota-scope=user --uid="$UTILISATEUR"

# 3. Compartiment, créé PAR l'utilisateur thanos (il en est propriétaire). Pas de versionnage : le
#    Compactor supprime lui-même les blocs remplacés ou expirés ; avec le versionnage, chaque
#    suppression laisserait une version cachée qui remplirait le quota. Pas de règle de cycle de vie
#    non plus : la rétention appartient au Compactor (M21-E25), une expiration côté RGW couperait
#    des blocs au milieu d'une compaction.
(
  set -a
  # shellcheck source=/dev/null
  . "$ENV_FICHIER"
  set +a
  if aws s3api head-bucket --bucket "$COMPARTIMENT" >/dev/null 2>&1; then
    echo "compartiment $COMPARTIMENT : existe déjà"
  else
    aws s3api create-bucket --bucket "$COMPARTIMENT" >/dev/null
    echo "compartiment $COMPARTIMENT créé"
  fi
  # Contrôles : l'utilisateur liste son compartiment ; il ne peut pas en créer un second.
  aws s3api list-objects-v2 --bucket "$COMPARTIMENT" --max-items 1 >/dev/null
  if aws s3api create-bucket --bucket "${COMPARTIMENT}-essai" >/dev/null 2>&1; then
    aws s3api delete-bucket --bucket "${COMPARTIMENT}-essai" >/dev/null 2>&1 || true
    echo "ATTENTION : un second compartiment a pu être créé (--max-buckets non appliqué ?)" >&2
    exit 1
  fi
  echo "contrôles : liste autorisée, second compartiment refusé (max-buckets=1)"
)

# 4. État, sans secret : quota et statistiques.
rgw user info --uid="$UTILISATEUR" | jq '{user_id, max_buckets, user_quota}'
