# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E20.sh — M19-E20 : Le même pipeline en Jenkinsfile
# À lancer depuis adm01. Lecture seule : API de Jenkins (compte wb-checks), API GitLab (fichiers).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E20 — Le même pipeline en Jenkinsfile"
require_cmd jq curl

check_cmd "mediagenda/api : Jenkinsfile sur la branche essai-jenkins" _m19o_fichier "$_M19O_P_API" Jenkinsfile essai-jenkins
_m19o_e20_f="${WB_M19_JENKINS_CHECKS_FILE:-$HOME/.config/workbook/jenkins-checks.env}"
if [[ ! -r "$_m19o_e20_f" ]]; then
  skip "contrôles de l'API de Jenkins" "identifiants absents : $_m19o_e20_f (M19-E19, étape 5)"
else
  _m19o_e20_b="$(_m19o_jenkins 'job/mediagenda-api/lastBuild/api/json?tree=result,builtOn,actions[lastBuiltRevision[branch[name]]]')"
  check_cmd "job mediagenda-api : dernier build réussi" _m19o_json "$_m19o_e20_b" '.result == "SUCCESS"'
  check_cmd "… construit depuis la branche essai-jenkins" _m19o_json "$_m19o_e20_b" \
    '[.actions[]?.lastBuiltRevision?.branch[]?.name // empty] | any(test("essai-jenkins$"))'
  check_cmd "… avec un rapport de tests publié (étape junit)" \
    _m19o_json "$(_m19o_jenkins 'job/mediagenda-api/lastBuild/testReport/api/json?tree=passCount,failCount')" \
    '(.passCount + .failCount) > 0'
fi
_m19o_e20_doc="$(_m19o_contenu "$_M19O_P_DOC" docs/livraison/ci/comparatif-jenkins.md)"
check_cmd "plateforme/medisphere (main) : docs/livraison/ci/comparatif-jenkins.md" test -n "$_m19o_e20_doc"
check_cmd "le comparatif contient des durées mesurées (au moins 4 valeurs en s ou min)" \
  bash -c '(( $(grep -oE "[0-9]+ ?(s|min)\b" <<<"$1" | wc -l) >= 4 ))' _ "$_m19o_e20_doc"
check_cmd "le comparatif traite des deux outils et conclut" \
  bash -c 'grep -qi "jenkins" <<<"$1" && grep -qi "gitlab" <<<"$1" && grep -qiE "^#+ *conclusion" <<<"$1"' _ "$_m19o_e20_doc"
