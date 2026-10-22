# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E13.sh — M20-E13 « Helm et Kustomize dans Argo CD, sources multiples ». Lecture seule :
# plateforme/charts-miroir (GitLab), Harbor (artefact et signature), AppProject plateforme (wb-checks),
# dépôts déclarés dans Argo CD (API, jeton en lecture).

# shellcheck source=_m20-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m20-operationnel.sh"

title "M20-E13 — Helm et Kustomize dans Argo CD, sources multiples"
require_cmd jq kubectl curl yq

_e13_p=plateforme/charts-miroir
_e13_charts="$(_m20o_gl_fichier "$_e13_p" charts.yaml | yq -o json -I0 '.' 2>/dev/null)" || _e13_charts=""
check_cmd "$_e13_p : charts.yaml sur main" _m20o_jq "$_e13_charts" '.charts | type == "array"'
check_cmd "charts.yaml : argo-rollouts à une version exacte, avec empreinte SHA-256" \
  _m20o_jq "$_e13_charts" '[.charts[]? | select(.nom == "argo-rollouts")
    | select((.version | tostring | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and (.empreinte | test("^sha256:[a-f0-9]{64}$")))] | length == 1'
check_cmd "charts.yaml : toutes les entrées ont une empreinte" \
  _m20o_jq "$_e13_charts" '(.charts | length) > 0 and ([.charts[] | (.empreinte // "") | test("^sha256:[a-f0-9]{64}$")] | all)'
check_cmd "$_e13_p : .gitlab-ci.yml sur main" _m20o_gl_existe "$_e13_p" .gitlab-ci.yml
check_cmd "$_e13_p : dernier pipeline de main réussi" _m20o_pipeline_ok "$_e13_p"
_e13_planif() {
  gitlab_api "projects/$(_m20o_enc "$_e13_p")/pipeline_schedules" 2>/dev/null | jq -e '[.[] | select(.active == true)] | length >= 1' >/dev/null 2>&1
}
check_cmd "$_e13_p : pipeline planifié actif" _e13_planif
_e13_protege() {
  _m20o_gl_fichier "$_e13_p" .gitlab-ci.yml | yq -o json -I0 '.' 2>/dev/null \
    | jq -e '[to_entries[] | select(.value | type == "object" and has("script")) | .value
             | select((.script | tostring | test("recopier|signer")))] as $j
             | ($j | length) >= 2 and ($j | all((.tags // []) | index("protege") != null))' >/dev/null 2>&1
}
check_cmd "$_e13_p : recopie et signature sur le runner protégé (étiquette protege)" _e13_protege

_e13_v="$(jq -r '[.charts[]? | select(.nom == "argo-rollouts")][0].version // ""' <<<"${_e13_charts:-null}" 2>/dev/null)" || _e13_v=""
if [[ -n "$_e13_v" ]]; then
  check_cmd "Harbor : charts/argo-rollouts:$_e13_v présent et signé (référent Cosign)" \
    _m20o_harbor_signe charts argo-rollouts "$_e13_v"
else
  check_cmd "Harbor : charts/argo-rollouts présent et signé" false
fi

_e13_proj="$(_m20o_obj argocd appprojects.argoproj.io plateforme)"
check_cmd "AppProject plateforme : source registry.par1.medisphere.internal/charts autorisée" \
  _m20o_jq "$_e13_proj" '(.spec.sourceRepos // []) | index("registry.par1.medisphere.internal/charts") != null'
check_cmd "AppProject plateforme : aucune source d'Internet ni joker global" \
  _m20o_jq "$_e13_proj" '(.spec.sourceRepos // []) | all(test("^(https://git01\\.par1\\.medisphere\\.internal/|registry\\.par1\\.medisphere\\.internal/)"))'

_e13_repos="$(_m20o_argocd_api repositories || true)"
if [[ -n "$_e13_repos" ]]; then
  check_cmd "Argo CD : dépôt Helm OCI registry.par1.medisphere.internal/charts déclaré et joignable" \
    _m20o_jq "$_e13_repos" '[.items[]? | select(.repo == "registry.par1.medisphere.internal/charts" and .enableOCI == true
      and .connectionState.status == "Successful")] | length == 1'
else
  skip "Argo CD : dépôt Helm OCI de Harbor" "API d'Argo CD illisible : jeton $_m20o_argocd_jeton absent ou refusé (M20-E03)"
fi
_e13_essai_absente() { _m20o_lisible applications.argoproj.io argocd && [[ -z "$(_m20o_app essai-multisources)" ]]; }
check_cmd "Application d'essai essai-multisources supprimée après la comparaison" _e13_essai_absente
check_cmd "journal ~/m20/e13/journal.md : comparaison des deux rendus notée" \
  _m20o_fichier_contient "$_m20o_brouillons/e13/journal.md" 'rendu'
