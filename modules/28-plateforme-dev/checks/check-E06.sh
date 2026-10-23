# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E06.sh — M28-E06 : Backstage : construire et installer le portail
# Lecture seule : Application, Deployment, Cluster CNPG (kube) ; HTTPS du portail ; API du catalogue
# avec le jeton des checks (et un appel REFUSÉ hors catalogue) ; client Keycloak (keycloak_api) ;
# projet plateforme/portail et son pipeline (GitLab, GET).

# shellcheck source=_m28-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m28-operationnel.sh"

title "M28-E06 — Backstage : construire et installer le portail"
require_cmd jq kubectl curl

# --- 1. Le projet ---------------------------------------------------------------------------------------------
check_cmd "plateforme/portail : Dockerfile multi-étapes, base de Harbor par empreinte" \
  _m28d_contient plateforme/portail Dockerfile 'FROM registry\.par1\.medisphere\.internal/.+@sha256:' 'AS build'
check_cmd "plateforme/portail : app-config.production.yaml (PostgreSQL en schémas, OIDC, accès externe limité au catalogue)" \
  _m28d_contient plateforme/portail app-config.production.yaml 'pluginDivisionMode: *schema' 'oidc' 'externalAccess' 'plugin: *catalog'
check_cmd "plateforme/portail : aucun fournisseur invité ni secret en clair dans la configuration de production" \
  _m28d_ne_contient_pas plateforme/portail app-config.production.yaml '^[[:space:]]*guest:|(clientSecret|secret|token|password):[[:space:]]*[^$[:space:]{]'
check_cmd "plateforme/portail : catalog-info.yaml présent" _m28d_contient plateforme/portail catalog-info.yaml 'kind: *Component'
check_cmd "plateforme/portail : dernier pipeline de main réussi" _m28d_pipeline_vert plateforme/portail

# --- 2. Le déploiement -----------------------------------------------------------------------------------------
check_cmd "Application Argo CD portail : Synced et Healthy" _m28d_app_saine portail
check_cmd "portail/portail prêt, image plateforme/portail de Harbor épinglée par empreinte" _m28d_deploy_pret \
  portail portail '^registry\.par1\.medisphere\.internal/plateforme/portail(:[^@]+)?@sha256:[a-f0-9]{64}$'
check_cmd "pod du portail : utilisateur non-root numérique, arguments --config de production" _m28d_kq \
  '.spec.template.spec.securityContext.runAsNonRoot == true and (.spec.template.spec.securityContext.runAsUser // 0) > 0
   and ((.spec.template.spec.containers[0].args // []) | index("app-config.production.yaml") != null)' \
  -n portail deployment portail
check_cmd "base portail-db saine (CloudNativePG)" _m28d_kq \
  '.status.phase == "Cluster in healthy state"' -n portail clusters.postgresql.cnpg.io portail-db

# --- 3. Ce que voit l'utilisateur ---------------------------------------------------------------------------------
check_http "https://portail… : disponibilité (/.backstage/health/v1/readiness), certificat valide" \
  "$_m28d_portail/.backstage/health/v1/readiness" 200
check_cmd "le jeton des checks lit le catalogue" bash -c \
  '[[ "$(jq -r "type" <<<"$1" 2>/dev/null)" == array ]]' _ "$(backstage_api 'catalog/entities?limit=1' 2>/dev/null || true)"
check_cmd "le jeton des checks est REFUSÉ hors du catalogue (scaffolder : 401 ou 403)" bash -c \
  '[[ "$1" == 401 || "$1" == 403 ]]' _ "$(_m28o_code_http "$_m28d_portail/api/scaffolder/v2/tasks" jeton)"
check_cmd "sans jeton, l'API du catalogue est refusée (401)" bash -c \
  '[[ "$1" == 401 ]]' _ "$(_m28o_code_http "$_m28d_portail/api/catalog/entities?limit=1")"

# --- 4. Le client OIDC ---------------------------------------------------------------------------------------------
check_cmd "Keycloak : client backstage confidentiel, une seule URI de redirection (…/api/auth/oidc/handler/frame)" bash -c \
  'jq -e ".[0].publicClient == false and (.[0].redirectUris == [\"$2/api/auth/oidc/handler/frame\"])" >/dev/null <<<"$1"' \
  _ "$(keycloak_api 'clients?clientId=backstage' 2>/dev/null | jq -c '[.[] | {publicClient, redirectUris}]' 2>/dev/null || true)" "$_m28d_portail"

check_cmd "plateforme/medisphere : docs/plateforme-dev/portail.md (couches, secrets, mise à jour)" \
  _m28d_doc docs/plateforme-dev/portail.md 'app-config\.production' 'kv/plateforme/portail' 'retour arri'
