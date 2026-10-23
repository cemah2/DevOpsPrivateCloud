# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # requêtes LogQL et filtres jq entre apostrophes
#
# check-E35.sh — M24-E35 « Panne : plus personne n'entre dans Grafana » : le client grafana a son URI
# de redirection exacte et la portée « groupes », Keycloak accepte la demande d'autorisation, la
# revendication groups est en noms courts ; une connexion SSO à Grafana a réussi APRÈS la dernière
# erreur de ce client (événements de Keycloak dans Loki, locataire audit) ; alerte sur les erreurs de
# client chargée ; contrôle de dérive planifié de plateforme/identite ; RB-246 ; journal ; panne close.
# Lecture seule (wb-checks de Keycloak, Loki, GitLab ; demande d'autorisation sans connexion).

# shellcheck source=_m24-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-expert.sh"

title "M24-E35 — Plus personne n'entre dans Grafana"
require_cmd jq curl

_m24x_e35_rappel="${WB_GRAFANA_URL:-https://grafana.apps.par1.medisphere.internal}/login/generic_oauth"

# --- 1. Le client ----------------------------------------------------------------------------------------
_m24x_e35_client="$(_m24d_kc_client grafana)"
check_cmd "Keycloak : client grafana actif, une seule URI de redirection exacte ($_m24x_e35_rappel)" \
  _m24d_json "$_m24x_e35_client" '.enabled == true and .redirectUris == [$r]' --arg r "$_m24x_e35_rappel"
check_output "Keycloak accepte la demande d'autorisation de grafana vers cette URI (formulaire, pas d'erreur)" '^200$' \
  _m24x_code_auth grafana "$_m24x_e35_rappel"
check_cmd "Client grafana : portée par défaut « groupes » (revendication groups)" \
  grep -qx groupes <<<"$(_m24x_portees_defaut grafana)"
check_cmd "Portée groupes : mappeur groups en noms courts (chemin complet désactivé), ID token et jeton d'accès" \
  _m24x_noms_courts

# --- 2. Une vraie connexion, après la dernière erreur --------------------------------------------------------
_m24x_e35_ok="$(_m24x_loki_dernier '{service="keycloak"} |= "CODE_TO_TOKEN" |= "grafana" | json | line_format "{{.message}}" |~ "type=\"CODE_TO_TOKEN\"" |~ "clientId=\"grafana\""' audit 3h)"
_m24x_e35_ko="$(_m24x_loki_dernier '{service="keycloak"} |= "_ERROR" |= "grafana" | json | line_format "{{.message}}" |~ "clientId=\"grafana\"" |~ "error=\"(invalid_client|invalid_client_credentials|invalid_redirect_uri|unauthorized_client)\""' audit 3h)"
if [[ -z "$_m24x_e35_ok" || -z "$_m24x_e35_ko" ]]; then
  _ko "Loki (audit) ne répond pas : impossible de prouver une connexion à Grafana (lab/bin/check 24 26)"
else
  check_cmd "Une connexion SSO à Grafana (CODE_TO_TOKEN du client grafana) dans les 3 dernières heures, après toute erreur de ce client" \
    _m24x_apres "$_m24x_e35_ok" "$_m24x_e35_ko"
fi

# --- 3. Prévention ------------------------------------------------------------------------------------------
check_cmd "Ruler de Loki (audit) : une alerte sur les erreurs de client (secret ou redirection refusés)" \
  _m24x_ruler_qui audit 'invalid_client|invalid_redirect_uri'
_m24x_e35_ci="$(_m24d_contenu_main plateforme/identite .gitlab-ci.yml)"
check_cmd "plateforme/identite : .gitlab-ci.yml contient un plan en code de sortie détaillé pour les pipelines planifiés" \
  _m24p_tous "$_m24x_e35_ci" 'detailed-exitcode' 'CI_PIPELINE_SOURCE *== *"schedule"'
_m24x_e35_planifie() {
  local p ids id
  p="$(_m24d_uri plateforme/identite)"
  ids="$(gitlab_api "projects/$p/pipelines?ref=main&source=schedule&per_page=10" 2>/dev/null | jq -r '.[].id' 2>/dev/null || true)"
  for id in $ids; do
    if gitlab_api "projects/$p/pipelines/$id/jobs?per_page=100" 2>/dev/null \
      | jq -e 'any(.[]; (.name | test("deriv"; "i")) and (.status == "success" or .status == "failed"))' >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}
check_cmd "plateforme/identite : un pipeline planifié de main a exécuté le contrôle de dérive (job « …deriv… »)" _m24x_e35_planifie
check_cmd "RB-246 sur main : section « un service refuse le retour du SSO »" \
  _m24x_section "$(_m24x_rb246)" 'retour du SSO|refuse.*SSO|client.*(secret|redirection)'
check_cmd "Journal de diagnostic M24-E35 sur main (docs/socle/journal/)" _m24x_journal E35
check_cmd "Panne M24-E35 close (lab/bin/break 24 35 --annuler après réparation)" _m24x_panne_close E35
