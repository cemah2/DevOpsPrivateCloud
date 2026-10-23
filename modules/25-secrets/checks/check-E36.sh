# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E36.sh — M25-E36 « Panne : la CI ne lit plus ses secrets » : la méthode gitlab/ est de nouveau
# configurée par la découverte OIDC de git01 (ni jwks_url, ni clé recopiée) ; le rôle ci-mediagenda-api
# lie l'audience openbao.medisphere.internal, ref_protected en CHAÎNE "true" avec le type glob, et porte
# la politique ci-mediagenda-api ; les autres rôles ci-* connus gardent la même audience et la même
# chaîne ; le dernier pipeline de main de mediagenda/api a réussi ; le contrôle de dérive des rôles
# tourne dans la CI de plateforme/secrets ; journal INC-5236.
# Lecture seule : bao_api (wb-checks : auth/+/config, auth/+/role/+), gitlab_api.

# shellcheck source=_m25-expert-b.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert-b.sh"

title "M25-E36 — Panne : la CI ne lit plus ses secrets"
require_cmd curl jq
_m25p_connexion

_m25y_e36_conf="$(_m25p_bao auth/gitlab/config)"
check_cmd "méthode gitlab/ : découverte OIDC de git01, sans jwks_url ni clé recopiée" \
  _m25p_jq "$_m25y_e36_conf" '
    .data.oidc_discovery_url == "https://git01.par1.medisphere.internal"
    and (.data.jwks_url // "") == ""
    and ((.data.jwt_validation_pubkeys // []) | length) == 0
    and .data.bound_issuer == "https://git01.par1.medisphere.internal"'

_m25y_e36_role="$(_m25p_bao auth/gitlab/role/ci-mediagenda-api)"
check_cmd "rôle ci-mediagenda-api : audience openbao.medisphere.internal (celle des id_tokens des jobs)" \
  _m25p_jq "$_m25y_e36_role" '.data.bound_audiences == ["openbao.medisphere.internal"]'
check_cmd "rôle ci-mediagenda-api : ref_protected lié à la CHAÎNE \"true\" (pas au booléen), type glob" \
  _m25p_jq "$_m25y_e36_role" '([.data.bound_claims.ref_protected] | flatten) == ["true"] and .data.bound_claims_type == "glob"'
check_cmd "rôle ci-mediagenda-api : références main et v* acceptées" \
  _m25p_jq "$_m25y_e36_role" '[.data.bound_claims.ref] | flatten | (index("main") != null and index("v*") != null)'
check_cmd "rôle ci-mediagenda-api : porte la politique ci-mediagenda-api" \
  _m25p_jq "$_m25y_e36_role" '(.data.token_policies // []) | index("ci-mediagenda-api") != null'

# Les autres rôles de M25-E10 : même audience, même chaîne (une erreur « harmonisée » touche souvent tous
# les rôles). Un rôle absent (projet non migré) est ignoré.
for _m25y_e36_r in ci-mediagenda-api-promotion ci-medidoc-medidoc ci-medidoc-medidoc-promotion ci-plateforme-secrets; do
  _m25y_e36_j="$(_m25p_bao "auth/gitlab/role/$_m25y_e36_r")"
  if [[ "$_m25y_e36_j" == null ]]; then
    skip "rôle $_m25y_e36_r : audience et ref_protected" "rôle absent ou illisible"
    continue
  fi
  check_cmd "rôle $_m25y_e36_r : audience openbao.medisphere.internal et ref_protected = \"true\" (chaîne)" \
    _m25p_jq "$_m25y_e36_j" '.data.bound_audiences == ["openbao.medisphere.internal"]
      and ([.data.bound_claims.ref_protected] | flatten) == ["true"]'
done

_m25y_e36_pipeline() {
  local p
  p="$(jq -rn --arg v mediagenda/api '$v | @uri')"
  gitlab_api "projects/$p/pipelines?ref=main&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
}
check_cmd "mediagenda/api : dernier pipeline de main réussi (signature comprise)" _m25y_e36_pipeline

_m25y_e36_ci() {
  local ci
  ci="$(_m25p_fichier "$_M25P_SECRETS" .gitlab-ci.yml)" || return 1
  grep -q 'verifier-roles-ci' <<<"$ci" && _m25p_fichier "$_M25P_SECRETS" outils/verifier-roles-ci.sh | grep -q 'bound_audiences'
}
check_cmd "plateforme/secrets : contrôle de dérive des rôles CI dans le pipeline (outils/verifier-roles-ci.sh)" _m25y_e36_ci
check_cmd "journal de diagnostic INC-5236 sur main (plateforme/medisphere)" _m25y_journal INC-5236
