# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E11.sh — M13-E11 : Renovate auto-hébergé
# À lancer depuis adm01. Lecture seule : GitLab en GET (projets, planifications, pipelines,
# variables, utilisateurs, MR).

# shellcheck source=_m13-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-operationnel.sh"

title "M13-E11 — Renovate auto-hébergé"
require_cmd jq

_m13_runner="projects/plateforme%2Frenovate-runner"
_m13_ren="projects/plateforme%2Frenovate"
_m13_cfg="projects/plateforme%2Frenovate-config"

_m13_tag_runner() { gitlab_api "$_m13_runner/repository/tags/v26.1.0" >/dev/null 2>&1; }
check_cmd "plateforme/renovate-runner : étiquette v26.1.0 importée" _m13_tag_runner
_m13_ci="$(_m13d_contenu_main "$_m13_ren" .gitlab-ci.yml)"
check_cmd "plateforme/renovate (main) : inclut le gabarit importé à v26.1.0" \
  bash -c 'grep -q "plateforme/renovate-runner" <<<"$1" && grep -Eq "ref:[[:space:]]*[\"'"'"']?v26\.1\.0" <<<"$1"' _ "$_m13_ci"
check_cmd "plateforme/renovate (main) : image de Renovate par le cache ghcr de Harbor, épinglée" \
  bash -c 'grep -Eq "CI_RENOVATE_IMAGE:[[:space:]]*[\"'"'"']?$2/ghcr/renovatebot/renovate:44[^[:space:]]*@sha256:" <<<"$1"' _ "$_m13_ci" "$_M13D_NOM"
check_cmd "plateforme/renovate (main) : config.js présent" _m13d_fichier_main "$_m13_ren" config.js
_m13_planif() { gitlab_api "$_m13_ren/pipeline_schedules" 2>/dev/null | jq -e '[.[] | select(.active == true and .ref == "main")] | length >= 1' >/dev/null 2>&1; }
check_cmd "plateforme/renovate : planification active sur main" _m13_planif
_m13_dernier() {
  gitlab_api "$_m13_ren/pipelines?source=schedule&per_page=1" 2>/dev/null | jq -e '.[0].status == "success"' >/dev/null 2>&1
}
check_cmd "plateforme/renovate : dernier pipeline planifié réussi" _m13_dernier
check_cmd "plateforme/renovate : RENOVATE_TOKEN protégée et masquée" \
  jq -e '.protected == true and .masked == true' <<<"$(_m13o_var_projet plateforme%2Frenovate RENOVATE_TOKEN)"

_m13_bot="$(gitlab_api "users?username=renovate-bot" 2>/dev/null | jq -c '.[0] // empty' 2>/dev/null || true)"
check_cmd "GitLab : utilisateur renovate-bot existe, actif" jq -e '.state == "active"' <<<"${_m13_bot:-null}"
_m13_bot_admin() { [[ -n "$_m13_bot" ]] && jq -e '(.is_admin // false) == false' <<<"$_m13_bot" >/dev/null 2>&1; }
check_cmd "GitLab : renovate-bot n'est pas administrateur" _m13_bot_admin

# --- Préréglage --------------------------------------------------------------------------------------------
_m13_pre="$(_m13d_contenu_main "$_m13_cfg" default.json)"
check_cmd "renovate-config (main) : default.json est du JSON valide" jq -e 'type == "object"' <<<"${_m13_pre:-null}"
check_cmd "préréglage : images épinglées par empreinte (pinDigests)" \
  jq -e '(.pinDigests == true) or ([.packageRules[]? | select(.pinDigests == true)] | length >= 1)' <<<"${_m13_pre:-null}"
check_cmd "préréglage : alias des caches Harbor (dockerhub → docker.io)" \
  jq -e --arg r "$_M13D_NOM/dockerhub" '(.registryAliases[$r] // "") | test("docker\\.io")' <<<"${_m13_pre:-null}"
check_cmd "préréglage : délai de maturité (minimumReleaseAge) d'au moins 3 jours" \
  jq -e '(.minimumReleaseAge // "") | test("^([3-9]|[1-9][0-9]+) days?$")' <<<"${_m13_pre:-null}"
check_cmd "préréglage : fusion automatique limitée aux correctifs" \
  jq -e '(.automerge // false) == false
         and ([.packageRules[]? | select(.automerge == true)] | length >= 1)
         and all(.packageRules[]? | select(.automerge == true); (.matchUpdateTypes // []) == ["patch"])
         and ((.ignoreTests // false) == false)' <<<"${_m13_pre:-null}"

# --- Projets traités -----------------------------------------------------------------------------------------
for _m13_p in mediagenda%2Fapi medidoc%2Fmedidoc medinotif%2Fworker legacy%2Flegacy-rdv plateforme%2Fci-templates; do
  check_cmd "${_m13_p//%2F//} (main) : renovate.json étend local>plateforme/renovate-config" \
    jq -e '[.extends[]?] | index("local>plateforme/renovate-config")' <<<"$(_m13d_contenu_main "projects/$_m13_p" renovate.json || true)"
done
_m13_mr() {
  gitlab_api "projects/mediagenda%2Fapi/merge_requests?author_username=renovate-bot&state=all&per_page=1" 2>/dev/null \
    | jq -e 'length >= 1' >/dev/null 2>&1
}
check_cmd "mediagenda/api : au moins une MR de renovate-bot" _m13_mr
check_cmd "docs/registre/renovate.md sur main" _m13o_doc docs/registre/renovate.md
