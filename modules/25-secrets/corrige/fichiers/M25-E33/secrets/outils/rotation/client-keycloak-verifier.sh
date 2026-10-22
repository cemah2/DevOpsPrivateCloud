#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# outils/rotation/client-keycloak-verifier.sh — après la rotation d'un client Keycloak (M25-E33) :
# 1. le NOUVEAU secret (lu dans le coffre) est accepté par Keycloak : on présente les identifiants au
#    point de jeton avec un grant que le client n'a pas le droit d'utiliser (client_credentials) :
#    Keycloak répond « unauthorized_client » si le secret est bon, « invalid_client » s'il est faux —
#    aucune session n'est créée ;
# 2. le consommateur a repris le secret (URL de santé donnée, 200 attendu) ;
# 3. l'ancien secret est invalidé (DELETE …/client-secret/rotated).
# Usage : client-keycloak-verifier.sh <CLIENT-ID> <CHEMIN-KV> <URL-SANTÉ-DU-CONSOMMATEUR>
# shellcheck source=commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"
besoin bao jq curl
client="${1:?usage}"; chemin="${2:?usage}"; sante="${3:?usage}"
kc="${KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"
royaume="${KEYCLOAK_ROYAUME:-medisphere}"

reponse="$(kv_champ "$chemin" client_secret \
  | curl -sS --max-time 20 -K <(printf 'user = "%s:%s"\n' "$client" "$(cat)") \
      -d grant_type=client_credentials "$kc/realms/$royaume/protocol/openid-connect/token" | jq -r '.error // "jeton"')"
case "$reponse" in
  unauthorized_client | jeton) journal "nouveau secret de $client accepté par Keycloak ($reponse)" ;;
  *) echec "nouveau secret de $client refusé par Keycloak ($reponse) : NE PAS invalider l'ancien" ;;
esac
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$sante")"
[[ "$code" == 200 ]] || echec "consommateur de $client en mauvaise santé ($sante : $code)"

id="$(kv_champ plateforme/rotation/keycloak client_id)"
jeton="$(kv_champ plateforme/rotation/keycloak client_secret \
  | curl -sS --fail-with-body --max-time 20 -K <(printf 'user = "%s:%s"\n' "$id" "$(cat)") \
      -d grant_type=client_credentials "$kc/realms/$royaume/protocol/openid-connect/token" | jq -er '.access_token')"
uuid="$(printf '%s' "$jeton" | curl_bearer "$kc/admin/realms/$royaume/clients?clientId=$client" | jq -er '.[0].id')"
printf '%s' "$jeton" | curl_bearer "$kc/admin/realms/$royaume/clients/$uuid/client-secret/rotated" -X DELETE >/dev/null \
  || echec "invalidation de l'ancien secret de $client"
unset jeton
journal "ancien secret de $client invalidé"
