# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E10.sh — M25-E10 « La CI sans secret durable : jetons d'identité de GitLab ».
# Vérifie : méthode gitlab/ de type jwt sur la découverte OIDC de GitLab, rôle ci-mediagenda-api
# (audience, project_id réel, ref_protected, durée), politiques au plus juste, secrets présents dans
# le coffre (métadonnées seulement), composant securite v2.9.0 avec .openbao-connexion, pipeline vert
# de mediagenda/api, plus de secret durable dans les variables du projet et du groupe, essais notés,
# pipeline de plateforme/secrets authentifié par son rôle.
# Lecture seule : bao_api (wb-checks), gitlab_api, ~/m25/e10/.

# shellcheck source=_m25-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-operationnel.sh"

title "M25-E10 — La CI sans secret durable : jetons d'identité de GitLab"
require_cmd jq curl

# --- Méthode gitlab/ -------------------------------------------------------------------------------
check_cmd "méthode d'authentification gitlab/ montée, de type jwt" _m25o_auth_type gitlab jwt
_m25o_e10_conf="$(_m25o_bao auth/gitlab/config)"
check_cmd "gitlab/ : découverte OIDC de git01 et émetteur lié (pas de clé recopiée à la main)" _m25o_json "$_m25o_e10_conf" '
  .data.oidc_discovery_url == "https://git01.par1.medisphere.internal"
  and .data.bound_issuer == "https://git01.par1.medisphere.internal"
  and ((.data.jwt_validation_pubkeys // []) | length) == 0'

# --- Rôle ci-mediagenda-api ------------------------------------------------------------------------
_m25o_e10_id="$(_m25o_projet_id "$_M25O_P_API")"
_m25o_e10_role="$(_m25o_bao auth/gitlab/role/ci-mediagenda-api)"
check_cmd "rôle ci-mediagenda-api : audience openbao.medisphere.internal" _m25o_json "$_m25o_e10_role" \
  '.data.bound_audiences == ["openbao.medisphere.internal"]'
check_cmd "rôle ci-mediagenda-api : lié au project_id réel de mediagenda/api (${_m25o_e10_id:-introuvable})" \
  _m25o_json "$_m25o_e10_role" --arg id "${_m25o_e10_id:-x}" \
  '[.data.bound_claims.project_id] | flatten | map(tostring) == [$id]'
check_cmd "rôle ci-mediagenda-api : références protégées seulement (ref_protected = \"true\", chaîne)" \
  _m25o_json "$_m25o_e10_role" '[.data.bound_claims.ref_protected] | flatten == ["true"]'
check_cmd "rôle ci-mediagenda-api : jetons de 10 minutes au plus, politique ci-mediagenda-api" \
  _m25o_json "$_m25o_e10_role" '
  (.data.token_ttl // 0) > 0 and (.data.token_ttl // 0) <= 600
  and (.data.token_max_ttl // 0) > 0 and (.data.token_max_ttl // 0) <= 600
  and (.data.token_policies | index("ci-mediagenda-api")) != null'
check_cmd "rôle ci-mediagenda-api-promotion : réservé à l'environnement promotion/*" \
  _m25o_json "$(_m25o_bao auth/gitlab/role/ci-mediagenda-api-promotion)" \
  '[.data.bound_claims.environment] | flatten | any(test("^promotion/"))'
check_cmd "rôle ci-plateforme-secrets : références protégées, politique tofu-secrets" \
  _m25o_json "$(_m25o_bao auth/gitlab/role/ci-plateforme-secrets)" \
  '([.data.bound_claims.ref_protected] | flatten == ["true"]) and (.data.token_policies | index("tofu-secrets")) != null'

# --- Politiques ------------------------------------------------------------------------------------
check_cmd "politique ci-mediagenda-api : lit le robot Harbor" \
  _m25o_politique_contient ci-mediagenda-api 'kv/data/plateforme/harbor/robot-ci'
check_cmd "politique ci-mediagenda-api : ni joker global sur kv/, ni accès au jeton de promotion (même par mediagenda/ci/*)" \
  _m25o_politique_exclut ci-mediagenda-api '"kv/(data/)?\*"|"kv/data/\+|mediagenda/(ci/)?(promotion|\*|\+)|"\*"'
check_cmd "politique ci-mediagenda-api-promotion : ne lit que le jeton de promotion" \
  _m25o_politique_exclut ci-mediagenda-api-promotion 'harbor|release|"\*"'
check_cmd "politique wb-checks étendue : configuration des rôles lisible, aucune donnée KV" \
  bash -c '[[ -n "$1" ]] && grep -Eq "auth/\+/role/(\*|\+)" <<<"$1" && grep -q "sys/leases/lookup/db-mediagenda" <<<"$1" && ! grep -Eq "kv/data|/creds/|/issue/|/sign/" <<<"$1"' _ \
  "$(_m25o_politique wb-checks)"

# --- Secrets dans le coffre (métadonnées) ----------------------------------------------------------
for _m25o_e10_kv in plateforme/harbor/robot-ci mediagenda/ci/promotion mediagenda/ci/release; do
  check_cmd "kv/$_m25o_e10_kv existe (valeur non lue)" _m25o_kv_existe "$_m25o_e10_kv"
done

# --- Composant et pipelines ------------------------------------------------------------------------
_m25o_e10_etiquette() { gitlab_api "projects/$(_m25o_uri "$_M25O_P_CI")/repository/tags/v2.9.0" >/dev/null 2>&1; }
check_cmd "plateforme/ci-templates : étiquette v2.9.0 publiée" _m25o_e10_etiquette
check_cmd "composant securite v2.9.0 : job .openbao-connexion avec id_tokens d'audience openbao.medisphere.internal" \
  bash -c 'c="$1"; [[ -n "$c" ]] && grep -q "^\.openbao-connexion:" <<<"$c" && grep -q "id_tokens:" <<<"$c" && grep -q "aud: openbao.medisphere.internal" <<<"$c"' _ \
  "$(_m25o_contenu "$_M25O_P_CI" templates/securite/template.yml v2.9.0)"
check_cmd "mediagenda/api : .gitlab-ci.yml consomme securite@v2.9.0" \
  _m25o_contient "$_M25O_P_API" .gitlab-ci.yml 'ci-templates/securite@v2\.(9|[1-9][0-9])\.'
check_cmd "mediagenda/api : dernier pipeline de main réussi" _m25o_pipeline_vert "$_M25O_P_API"

# --- Variables de CI : plus de secret durable ------------------------------------------------------
_m25o_e10_interdites='^(HARBOR_ROBOT_USER|HARBOR_ROBOT_TOKEN|DEPLOIEMENT_TOKEN|GITLAB_TOKEN|COSIGN_PRIVATE_KEY|COSIGN_PASSWORD)$'
for _m25o_e10_cible in "projects:$_M25O_P_API" "groups:mediagenda"; do
  _m25o_e10_vars="" _m25o_e10_rc=0
  _m25o_e10_vars="$(_m25o_variables "${_m25o_e10_cible%%:*}" "${_m25o_e10_cible#*:}")" || _m25o_e10_rc=$?
  if ((_m25o_e10_rc == 2)); then
    skip "variables de CI de ${_m25o_e10_cible#*:}" "le jeton des checks n'a pas le droit de les lister"
  else
    check_cmd "variables de CI de ${_m25o_e10_cible#*:} : plus de HARBOR_ROBOT_*, DEPLOIEMENT_TOKEN, GITLAB_TOKEN, COSIGN_*" \
      bash -c '! grep -Eq "$1" <<<"$2"' _ "$_m25o_e10_interdites" "$_m25o_e10_vars"
  fi
done

# --- plateforme/secrets se gère lui-même ------------------------------------------------------------
check_cmd "plateforme/secrets : .gitlab-ci.yml avec id_tokens et le rôle ci-plateforme-secrets" \
  bash -c 'c="$1"; [[ -n "$c" ]] && grep -q "id_tokens:" <<<"$c" && grep -q "ci-plateforme-secrets" <<<"$c"' _ \
  "$(_m25o_contenu "$_M25O_P_SECRETS" .gitlab-ci.yml)"
check_cmd "plateforme/secrets : dernier pipeline de main réussi" _m25o_pipeline_vert "$_M25O_P_SECRETS"

# --- Essais et documentation -----------------------------------------------------------------------
check_cmd "m25/e10/essais.md : refus sur branche non protégée noté (sans aucun jeton recopié)" \
  _m25o_local e10/essais.md 'does not match|permission denied|refus'
check_cmd "docs/securite/secrets/ci-et-openbao.md sur main" \
  _m25o_fichier "$_M25O_P_DOC" "$_M25O_DOC_SECRETS/ci-et-openbao.md"
