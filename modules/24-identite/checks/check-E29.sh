# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E29.sh — M24-E29 : Rotation des secrets des clients et des clés de signature
# À lancer depuis adm01. Lecture seule : JWKS public du royaume, clés et fournisseurs de clés (wb-checks),
# code OpenTofu et RB-244 sur main.

# shellcheck source=_m24-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-production.sh"

title "M24-E29 — Rotation des secrets des clients et des clés de signature"
require_cmd jq curl

_m24p_e29_jwks="$(_m24d_public /realms/medisphere/protocol/openid-connect/certs)"
check_cmd "JWKS du royaume : une seule clé de signature RS256 publiée (l'ancienne est désactivée)" _m24d_json "$_m24p_e29_jwks" \
  '[.keys[] | select(.use == "sig" and .alg == "RS256")] | length == 1'
_m24p_e29_fourn="$(_m24d_kc "components?type=org.keycloak.keys.KeyProvider")"
_m24p_e29_cles="$(_m24d_kc "keys")"
# shellcheck disable=SC2016  # $f, $ids : variables de jq
check_cmd "La clé RS256 active vient d'un fournisseur rsa-<AAAA-MM> (rotation faite par le code)" _m24d_json "$_m24p_e29_cles" \
  '([$f[] | select(.name | test("^rsa-[0-9]{4}-[0-9]{2}$")) | .id]) as $ids
   | any(.keys[]; .algorithm == "RS256" and .status == "ACTIVE" and (.providerId as $p | $ids | index($p) != null))' \
  --argjson f "${_m24p_e29_fourn:-[]}"

_m24p_e29_tf="$(_m24p_tofu_tout)"
check_cmd "tofu/ : clé décrite par keycloak_realm_keystore_rsa_generated" _m24d_contient "$_m24p_e29_tf" \
  'resource +"keycloak_realm_keystore_rsa_generated"'
check_cmd "tofu/ : secret de grafana imposé en écriture seule (client_secret_wo et sa version)" _m24p_tous "$_m24p_e29_tf" \
  'client_secret_wo +=' 'client_secret_wo_version +='
check_cmd "tofu/ : version du secret de grafana ≥ 2 (rotation faite)" _m24d_contient "$_m24p_e29_tf" \
  'grafana *= *([2-9]|[1-9][0-9]+)'
check_cmd "tofu/ : aucun secret littéral (client_secret = \"…\")" _m24p_aucun '^[[:space:]]*client_secret(_wo)?[[:space:]]*=[[:space:]]*"' "$_m24p_e29_tf"
_m24p_e29_graf="$(_m24d_kc_client grafana)"
check_cmd "Client grafana actif, confidentiel" _m24d_json "$_m24p_e29_graf" '.enabled == true and .publicClient == false'

_m24p_e29_rb="$(_m24p_arbre plateforme/medisphere "$_M24P_DOC/runbooks" | grep -Ei 'RB-244' | head -n 1 || true)"
_m24p_e29_c=""
[[ -n "$_m24p_e29_rb" ]] && _m24p_e29_c="$(_m24p_doc "$_m24p_e29_rb")"
check_cmd "RB-244 sur main : fenêtre mesurée (secondes) et attente avant désactivation" _m24p_tous "$_m24p_e29_c" \
  'fen[êe]tre.*[0-9]+ ?s\b' 'passive' '24 ?h|[0-9]+ ?heures'
check_cmd "RB-244 : rempli (aucune valeur <N> ou <AAAA-MM-JJ> laissée)" _m24p_sans_gabarit "$_m24p_e29_c"
