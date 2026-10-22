#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# outils/rotation/client-keycloak.sh — rotation SANS COUPURE du secret d'un client confidentiel
# Keycloak consommé par la plateforme (M25-E33, SEC-2633). Projet plateforme/secrets, job planifié.
#
# Usage : client-keycloak.sh <CLIENT-ID> <CHEMIN-KV>         ex. client-keycloak.sh grafana plateforme/grafana/oidc
#
# 1. jeton du compte de service svc-rotation (royaume medisphere, rôle manage-clients : Keycloak
#    26.8 exige manage-clients pour lire ou régénérer un secret) ; ses identifiants sont dans
#    kv/plateforme/rotation/keycloak ;
# 2. POST …/clients/<id>/client-secret : nouveau secret. Avec la politique de client « rotation des
#    secrets » (executor secret-rotation) du royaume, l'ANCIEN reste valable (« rotated secret ») le
#    temps que les consommateurs suivent : c'est ce qui évite la coupure ;
# 3. nouvelle version de kv/<CHEMIN-KV> champ client_secret ; ESO la reprend (refreshInterval 5 min
#    des secrets tournants, M25-E13) et Reloader redémarre le consommateur (M25-E15) ;
# 4. le job « verifier » (après 15 min) invalide l'ancien secret (DELETE …/client-secret/rotated)
#    une fois le consommateur vu sain.
# Rien ne s'affiche : les secrets passent de curl à jq à bao par des tubes.
# shellcheck source=commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/commun.sh"
besoin bao jq curl
client="${1:?usage : $0 <CLIENT-ID> <CHEMIN-KV>}"
chemin="${2:?usage : $0 <CLIENT-ID> <CHEMIN-KV>}"
kc="${KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"
royaume="${KEYCLOAK_ROYAUME:-medisphere}"

jeton_admin() {
  # client_credentials de svc-rotation : identifiants lus dans le coffre, passés par -K (fichier).
  local id
  id="$(kv_champ plateforme/rotation/keycloak client_id)"
  kv_champ plateforme/rotation/keycloak client_secret \
    | curl -sS --fail-with-body --max-time 20 -K <(printf 'user = "%s:%s"\n' "$id" "$(cat)") \
        -d grant_type=client_credentials "$kc/realms/$royaume/protocol/openid-connect/token" \
    | jq -er '.access_token'
}

uuid="$(jeton_admin | curl_bearer "$kc/admin/realms/$royaume/clients?clientId=$client" | jq -er '.[0].id')" \
  || echec "client $client introuvable dans le royaume $royaume"
journal "client $client ($uuid) : régénération du secret"
jeton_admin | curl_bearer "$kc/admin/realms/$royaume/clients/$uuid/client-secret" -X POST \
  | jq -jer '.value' | kv_ecrire_champ "$chemin" client_secret \
  || echec "régénération ou écriture dans kv/$chemin"
version="$(kv_meta "$chemin" '.data.current_version')"
journal "kv/$chemin : version $version écrite ; l'ancien secret reste valable jusqu'au job verifier"
