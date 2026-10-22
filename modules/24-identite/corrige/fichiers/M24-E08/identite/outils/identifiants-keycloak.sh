#!/usr/bin/env bash
# identifiants-keycloak.sh — affiche les identifiants à mettre dans tofu/imports.tf (M24-E08).
#
# Lecture seule : GET sur l'API d'administration avec le client svc-tofu-keycloak (royaume master),
# dont les identifiants viennent de ~/.config/workbook/keycloak-tofu.env (600) :
#   KEYCLOAK_CLIENT_ID=svc-tofu-keycloak
#   KEYCLOAK_CLIENT_SECRET=…
# Usage : outils/identifiants-keycloak.sh [ROYAUME]    (défaut : medisphere)
# Variables : KEYCLOAK_URL (défaut https://sso.par1.medisphere.internal), CA (défaut : racine du lab).
# Le jeton d'accès ne quitte jamais la mémoire du script (en-tête passé à curl par un fichier
# anonyme, jamais en argument visible dans ps).
set -euo pipefail

royaume="${1:-medisphere}"
url="${KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"
ca="${CA:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
acces="$HOME/.config/workbook/keycloak-tofu.env"

die() { echo "identifiants-keycloak : $*" >&2; exit 1; }

[[ -r "$acces" ]] || die "$acces introuvable"
[[ "$(stat -c %a "$acces")" == 600 ]] || die "$acces doit être en 600"
command -v jq >/dev/null || die "jq introuvable"
KEYCLOAK_CLIENT_ID="" KEYCLOAK_CLIENT_SECRET=""
# shellcheck source=/dev/null
. "$acces"
[[ -n "$KEYCLOAK_CLIENT_ID" && -n "$KEYCLOAK_CLIENT_SECRET" ]] || die "KEYCLOAK_CLIENT_ID ou KEYCLOAK_CLIENT_SECRET vide"

curl_ca=(--cacert "$ca")
[[ "$url" == https://* ]] || curl_ca=()

jeton="$(curl -sf "${curl_ca[@]}" -K <(printf 'user = "%s:%s"\n' "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET") \
  -d grant_type=client_credentials "$url/realms/master/protocol/openid-connect/token" | jq -r '.access_token // empty')" \
  || die "jeton refusé (secret, client, ou /realms/master filtré par HAProxy hors MGMT et runner01)"
[[ -n "$jeton" ]] || die "jeton vide"

# api CHEMIN — GET sur /admin/realms/<royaume>/CHEMIN
api() {
  curl -sf "${curl_ca[@]}" -K <(printf 'header = "Authorization: Bearer %s"\n' "$jeton") \
    "$url/admin/realms/$royaume/$1"
}

client_id() { api "clients?clientId=$1" | jq -r '.[0].id // empty'; }

ldap="$(api "components?type=org.keycloak.storage.UserStorageProvider" | jq -r '.[] | select(.providerId == "ldap") | "\(.name)\t\(.id)"')"
echo "Fédérations LDAP (nom, ID) :"
printf '  %s\n' "$ldap"
while IFS=$'\t' read -r nom id; do
  [[ -n "$id" ]] || continue
  echo "Mappeurs de la fédération $nom (nom, type, ID) :"
  api "components?parent=$id&type=org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
    | jq -r '.[] | "  \(.name)\t\(.providerId)\t\(.id)"'
done <<<"$ldap"

echo "Portées clientes ajoutées au royaume (nom, ID, mappeurs) :"
api "client-scopes" | jq -r '.[] | select(.name == "groupes") | "  \(.name)\t\(.id)", (.protocolMappers[]? | "    mappeur \(.name)\t\(.id)")'

for c in wb-checks essai-oidc realm-management; do
  printf 'Client %s : %s\n' "$c" "$(client_id "$c")"
done
wb="$(client_id wb-checks)"
rm_id="$(client_id realm-management)"
if [[ -n "$wb" && -n "$rm_id" ]]; then
  sa="$(api "clients/$wb/service-account-user" | jq -r '.id')"
  echo "Compte de service de wb-checks : $sa"
  echo "Rôles de realm-management attribués à wb-checks (nom, ID) :"
  api "users/$sa/role-mappings/clients/$rm_id" | jq -r '.[] | "  \(.name)\t\(.id)"'
fi
