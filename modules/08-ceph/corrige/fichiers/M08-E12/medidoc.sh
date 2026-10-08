#!/usr/bin/env bash
# medidoc.sh — M08-E12 (DEV-922) : compte RGW « medidoc », utilisateur racine, quotas.
# Depuis adm01. Idempotent : le compte et l'utilisateur racine ne sont créés que s'ils manquent.
# Les clés de l'utilisateur racine ne s'affichent JAMAIS : elles arrivent de ceph01 par un tube
# dans un fichier 600 de ~/.config/workbook/, à chiffrer dans le Vault « critique » puis à effacer.
# La suite (compartiments, utilisateurs IAM, politiques) se fait avec le profil aws de la racine
# (voir le corrigé), parce que c'est l'administration DU COMPTE, pas du cluster.
# shellcheck disable=SC2029  # développement local voulu dans les commandes ssh
set -euo pipefail
umask 077

ADMIN=${WB_CEPH_ADMIN:-ceph01}
COMPTE=medidoc
COURRIEL=medidoc@medisphere.internal
RACINE=medidoc-racine
QUOTA_COMPTE=20G
QUOTA_OBJETS=1000000
SORTIE="$HOME/.config/workbook/s3-medidoc-racine.json"

r() { ssh -o BatchMode=yes "$ADMIN" "sudo radosgw-admin $(printf '%q ' "$@")" 2>/dev/null; }

if ! compte="$(r account get --account-name="$COMPTE")"; then
  echo "== Création du compte $COMPTE"
  compte="$(r account create --account-name="$COMPTE" --email="$COURRIEL")"
fi
ID="$(jq -r .id <<<"$compte")"
[[ "$ID" =~ ^RGW[0-9]{17}$ ]] || { echo "identifiant de compte inattendu : $ID" >&2; exit 1; }
echo "compte $COMPTE : $ID"

if r user info --uid="$RACINE" >/dev/null; then
  echo "utilisateur racine $RACINE : déjà présent (clés non réaffichées)"
else
  echo "== Utilisateur racine $RACINE (clés → $SORTIE, 600)"
  r user create --uid="$RACINE" --display-name="$RACINE" --account-id="$ID" --account-root \
    --gen-access-key --gen-secret | jq '{user_id, keys: [.keys[] | {access_key, secret_key}]}' > "$SORTIE"
  echo "À FAIRE : chiffrer $SORTIE dans le Vault « critique », l'inscrire au registre, puis : shred -u $SORTIE"
fi

echo "== Quotas"
r quota set --quota-scope=account --account-id="$ID" --max-size="$QUOTA_COMPTE" >/dev/null
r quota enable --quota-scope=account --account-id="$ID" >/dev/null
r quota set --quota-scope=bucket --account-id="$ID" --max-objects="$QUOTA_OBJETS" >/dev/null
r quota enable --quota-scope=bucket --account-id="$ID" >/dev/null
r account get --account-id="$ID" | jq '{id, name, quota, bucket_quota}'
