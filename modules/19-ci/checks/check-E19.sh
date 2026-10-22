# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E19.sh — M19-E19 : Jenkins dans Kubernetes : JCasC et agents en pods
# À lancer depuis adm01. Lecture seule : API de Jenkins (compte wb-checks, lecture :
# WB_M19_JENKINS_CHECKS_FILE, défaut ~/.config/workbook/jenkins-checks.env avec JENKINS_USER et
# JENKINS_TOKEN), « kube » (pods des espaces jenkins et sonarqube).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E19 — Jenkins dans Kubernetes : JCasC et agents en pods"
require_cmd jq curl kubectl

_m19o_e19_pods="$(_m19o_k get pods -n jenkins -o json)"
check_cmd "espace jenkins : contrôleur prêt" _m19o_json "$_m19o_e19_pods" \
  'any(.items[]; .metadata.labels["app.kubernetes.io/component"] == "jenkins-controller" and any(.status.conditions[]?; .type == "Ready" and .status == "True"))'
check_cmd "contrôleur : image jenkins 2.580.x en Java 21, par Harbor" _m19o_json "$_m19o_e19_pods" \
  'any(.items[].spec.containers[]; .image | test("^registry\\.par1\\.medisphere\\.internal/.*jenkins/jenkins:2\\.580\\.[0-9]+-jdk21"))'
check_cmd "espace jenkins : aucun conteneur privilégié" _m19o_json "$_m19o_e19_pods" \
  '[.items[] | (.spec.containers + (.spec.initContainers // []))[] | select(.securityContext.privileged == true)] | length == 0'
# Espace absent ou vide (SonarQube retiré) : aucun pod, c'est conforme ; cluster illisible : KO.
_m19o_e19_sq="$(_m19o_k get pods -n sonarqube -o json)"
if [[ -z "$_m19o_e19_sq" ]] && _m19o_json "$(_m19o_k get namespaces -o json)" 'all(.items[]; .metadata.name != "sonarqube")'; then
  _m19o_e19_sq='{"items":[]}'
fi
check_cmd "espace sonarqube : SonarQube arrêté (aucun pod SonarQube)" _m19o_json "$_m19o_e19_sq" \
  '[.items[]? | select(.metadata.labels.app == "sonarqube")] | length == 0'

_m19o_e19_anon="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$_M19O_JENKINS_URL/api/json" 2>/dev/null || echo 000)"
check_cmd "accès anonyme à l'API refusé (reçu HTTP $_m19o_e19_anon, attendu 401 ou 403)" bash -c '[[ "$1" == 401 || "$1" == 403 ]]' _ "$_m19o_e19_anon"

_m19o_e19_f="${WB_M19_JENKINS_CHECKS_FILE:-$HOME/.config/workbook/jenkins-checks.env}"
if [[ ! -r "$_m19o_e19_f" ]]; then
  skip "contrôles de l'API de Jenkins" "identifiants absents : $_m19o_e19_f (jeton d'API du compte wb-checks, étape 5)"
else
  check_cmd "identifiants des vérifications en 600" _m19o_local600 "$_m19o_e19_f"
  _m19o_e19_api="$(_m19o_jenkins 'api/json?tree=description,numExecutors,mode')"
  check_cmd "configuration chargée par JCasC (message système attendu)" _m19o_json "$_m19o_e19_api" \
    '(.description // "") | test("JCasC")'
  check_cmd "aucun exécuteur sur le contrôleur" _m19o_json "$_m19o_e19_api" '.numExecutors == 0'
  _m19o_e19_b="$(_m19o_jenkins 'job/essai-agent/lastBuild/api/json?tree=result,builtOn,building')"
  check_cmd "job essai-agent : dernier build réussi" _m19o_json "$_m19o_e19_b" '.result == "SUCCESS"'
  check_cmd "… sur un agent en pod (pas sur le contrôleur)" _m19o_json "$_m19o_e19_b" \
    '(.builtOn // "") != "" and (.builtOn | test("built-in|master") | not)'
fi
