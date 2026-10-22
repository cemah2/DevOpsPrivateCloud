# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E41.sh — M19-E41 « Panne : les pipelines ne se déclenchent plus » : CI/CD activée, chemin de
# configuration par défaut, dernier commit de main avec son pipeline, workflow du composant qui garde
# les pipelines de branche, pipeline planifié dont le propriétaire est actif, RB-194, panne close.

# shellcheck source=_m19-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-expert.sh"

title "M19-E41 — Les pipelines se déclenchent à nouveau"
require_cmd jq yq curl

if _m19x_temoin_existe; then
  _m19_e41_p="projects/$(_m19x_enc "$_m19x_temoin")"
  check_cmd "témoin : CI/CD activée" _m19x_gl '.builds_access_level == "enabled"' "$_m19_e41_p"
  check_cmd "témoin : fichier de configuration CI par défaut (.gitlab-ci.yml)" \
    _m19x_gl '(.ci_config_path // "") | . == "" or . == ".gitlab-ci.yml"' "$_m19_e41_p"
  _m19_e41_tete_a_pipeline() {
    local sha
    sha="$(gitlab_api "$_m19_e41_p/repository/branches/main" 2>/dev/null | jq -r '.commit.id // empty')"
    [[ -n "$sha" ]] && gitlab_api "$_m19_e41_p/pipelines?sha=$sha&per_page=1" 2>/dev/null | jq -e 'length == 1' >/dev/null 2>&1
  }
  check_cmd "témoin : le dernier commit de main a déclenché un pipeline" _m19_e41_tete_a_pipeline
  _m19_e41_workflow() {
    _m19x_canari_gabarit | yq -e 'select(documentIndex == 1) | .workflow.rules | any_c(((.if // "") | test("CI_COMMIT_BRANCH")) and ((.when // "always") != "never"))' >/dev/null 2>&1
  }
  check_cmd "composant canari consommé : workflow:rules garde les pipelines de branche" _m19_e41_workflow
  _m19_e41_planifie() {
    gitlab_api "$_m19_e41_p/pipeline_schedules?per_page=100" 2>/dev/null |
      jq -e '[.[] | select(.description == "canari-quotidien")][0] | .active and .owner.state == "active"' >/dev/null 2>&1
  }
  check_cmd "pipeline planifié canari-quotidien actif, propriétaire actif (non bloqué)" _m19_e41_planifie
else
  skip "témoin $_m19x_temoin" "absent : il est créé à la première injection (lab/bin/break 19 41)"
fi
_m19_e41_rb() { _m19x_doc_contient 'RB-194*.md' 'workflow' && _m19x_doc_contient 'RB-194*.md' 'planifi'; }
check_cmd "RB-194 : « un pipeline ne se déclenche pas » (workflow, chemin, CI/CD désactivée, planifiés)" _m19_e41_rb
check_cmd "panne M19-E41 close (lab/bin/break 19 41 --annuler après réparation)" _m19x_aucune_panne_active E41
