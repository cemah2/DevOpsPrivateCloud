# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E16.sh — M19-E16 : SonarQube Community Build : installer et analyser
# À lancer depuis adm01. Lecture seule : API de SonarQube (jeton du compte wb-checks, droit Browse :
# WB_M19_SONAR_TOKEN_FILE, défaut ~/.config/workbook/sonar-checks.token), « kube » (pods de l'espace
# sonarqube), API GitLab (jobs, variables du projet).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E16 — SonarQube Community Build : installer et analyser"
require_cmd jq curl kubectl

_m19o_e16_jeton="${WB_M19_SONAR_TOKEN_FILE:-$HOME/.config/workbook/sonar-checks.token}"
if [[ ! -r "$_m19o_e16_jeton" ]]; then
  skip "contrôles de l'API SonarQube" "jeton absent : $_m19o_e16_jeton (crée le compte wb-checks et son jeton, étape 3)"
else
  check_cmd "jeton des vérifications en 600" _m19o_local600 "$_m19o_e16_jeton"
  _m19o_e16_st="$(_m19o_sonar system/status)"
  check_cmd "SonarQube répond UP sur $_M19O_SONAR_URL" _m19o_json "$_m19o_e16_st" '.status == "UP"'
  check_cmd "SonarQube est en 26.10 (Community Build)" _m19o_json "$_m19o_e16_st" '.version | startswith("26.10")'
  check_cmd "le projet mediagenda-api a au moins une analyse" \
    _m19o_json "$(_m19o_sonar 'project_analyses/search?project=mediagenda-api&ps=1')" '(.analyses | length) >= 1'
  check_cmd "la porte qualité de mediagenda-api a un statut (OK, WARN ou ERROR)" \
    _m19o_json "$(_m19o_sonar 'qualitygates/project_status?projectKey=mediagenda-api')" \
    '.projectStatus.status | test("^(OK|WARN|ERROR)$")'
fi
# Plus d'analyse anonyme : une requête sans jeton est refusée (401) par l'API de lecture d'un projet.
_m19o_e16_anon="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" \
  "$_M19O_SONAR_URL/api/project_analyses/search?project=mediagenda-api" 2>/dev/null || echo 000)"
check_cmd "accès anonyme refusé (reçu HTTP $_m19o_e16_anon, attendu 401 ou 403)" bash -c '[[ "$1" == 401 || "$1" == 403 ]]' _ "$_m19o_e16_anon"

_m19o_e16_pods="$(_m19o_k get pods -n sonarqube -o json)"
check_cmd "espace sonarqube : un pod SonarQube prêt" _m19o_json "$_m19o_e16_pods" \
  'any(.items[]; .metadata.labels.app == "sonarqube" and any(.status.conditions[]?; .type == "Ready" and .status == "True"))'
check_cmd "espace sonarqube : image sonarqube 26.10 par Harbor" _m19o_json "$_m19o_e16_pods" \
  'any(.items[].spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/.*sonarqube:26\\.10\\."))'
check_cmd "espace sonarqube : aucun conteneur privilégié (ni initSysctl)" _m19o_json "$_m19o_e16_pods" \
  '[.items[] | (.spec.containers + (.spec.initContainers // []))[] | select(.securityContext.privileged == true)] | length == 0'
check_cmd "espace sonarqube : base CNPG sonarqube-db prête" _m19o_json "$_m19o_e16_pods" \
  'any(.items[]; .metadata.labels["cnpg.io/cluster"] == "sonarqube-db" and any(.status.conditions[]?; .type == "Ready" and .status == "True"))'

# Job d'analyse dans un pipeline récent de main (statut indifférent : la porte informe pendant l'essai).
_m19o_e16_trouve=0
for _m19o_e16_id in $(_m19o_api "$_M19O_P_API/pipelines?ref=main&order_by=id&sort=desc&per_page=10" | jq -r '.[].id' 2>/dev/null || true); do
  if _m19o_json "$(_m19o_jobs "$_M19O_P_API" "$_m19o_e16_id")" 'any(.[]; .name == "sonarqube" and (.status == "success" or .status == "failed"))'; then
    _m19o_e16_trouve=1; break
  fi
done
check_cmd "mediagenda/api : un job sonarqube a tourné dans un pipeline récent de main" test "$_m19o_e16_trouve" = 1
_m19o_e16_var="$(_m19o_code "$_M19O_P_API/variables/SONAR_TOKEN")"
if [[ "$_m19o_e16_var" == 200 ]]; then
  check_cmd "mediagenda/api : SONAR_TOKEN protégée et masquée" \
    _m19o_json "$(_m19o_api "$_M19O_P_API/variables/SONAR_TOKEN")" '.protected == true and .masked == true'
elif [[ "$_m19o_e16_var" == 404 ]]; then
  check_cmd "mediagenda/api : variable SONAR_TOKEN présente" false
else
  skip "mediagenda/api : SONAR_TOKEN protégée et masquée" "API des variables refusée au jeton des checks (HTTP $_m19o_e16_var) : vérifie dans Settings > CI/CD > Variables"
fi
