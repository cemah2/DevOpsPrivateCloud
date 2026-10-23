# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E10.sh — M29-E10 : Le composant validation : une pyramide de tests en CI
# À lancer depuis adm01. Lecture seule : étiquette et gabarit de plateforme/ci-templates, CI et
# derniers pipelines de main des quatre dépôts consommateurs et de plateforme/politiques (API GitLab).
# WB_M29_VERSION_VALIDATION : étiquette publiée (v2.11.0 par défaut).

# shellcheck source=_m29-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-operationnel.sh"

title "M29-E10 — Le composant validation : une pyramide de tests en CI"
require_cmd jq curl

_m29o_e10_v="$_M29O_VERSION_VALIDATION"
check_cmd "plateforme/ci-templates : étiquette $_m29o_e10_v publiée" _m29o_etiquette_existe "$_M29O_P_CI" "$_m29o_e10_v"
_m29o_e10_t="$(_m29d_contenu "$_M29O_P_CI" templates/validation/template.yml "$_m29o_e10_v")"
check_cmd "composant validation@$_m29o_e10_v : entrées typées (spec:inputs) dont la version des schémas et celle des politiques" bash -c '
  grep -q "^spec:" <<<"$1" && grep -q "schemas_crd" <<<"$1" && grep -q "politiques" <<<"$1"' _ "$_m29o_e10_t"
check_cmd "composant : kubeconform -strict avec les schémas du paquet schemas-crd" bash -c '
  grep -q "kubeconform" <<<"$1" && grep -q -- "-strict" <<<"$1" && grep -q "packages/generic/schemas-crd" <<<"$1"' _ "$_m29o_e10_t"
check_cmd "composant : jamais -ignore-missing-schemas" bash -c '[[ -n "$1" ]] && ! grep -q -- "-ignore-missing-schemas" <<<"$1"' _ "$_m29o_e10_t"
check_cmd "composant : conftest (manifestes et plans) et opa test" bash -c '
  grep -q "conftest test" <<<"$1" && grep -q "opa test" <<<"$1"' _ "$_m29o_e10_t"
check_cmd "composant : Testinfra facultatif (entrée booléenne)" bash -c 'grep -Eq "testinfra" <<<"$1"' _ "$_m29o_e10_t"

# --- Consommateurs ------------------------------------------------------------------------------------
for _m29o_e10_p in plateforme/k8s plateforme/gitops plateforme/infra plateforme/ansible; do
  _m29o_e10_ci="$(_m29d_contenu "$_m29o_e10_p" .gitlab-ci.yml)"
  check_cmd "$_m29o_e10_p : inclut ci-templates/validation@vX.Y.Z (étiquette, pas une branche)" bash -c '
    grep -Eq "ci-templates/validation@v[0-9]+\.[0-9]+\.[0-9]+" <<<"$1"' _ "$_m29o_e10_ci"
done
check_cmd "plateforme/infra : les politiques des plans s'exécutent dans le job de plan" \
  _m29d_contient plateforme/infra .gitlab-ci.yml 'validation:conftest-plan'
# Le job de plan tourne sur runner01 (exécuteur shell) : conftest doit y être installé (rôle gitlab_runner).
_m29o_e10_runner() { remote runner01 'conftest --version' </dev/null 2>/dev/null | grep -Eq '^Conftest: 0\.71\.'; }
check_cmd "runner01 : conftest 0.71 installé (le job de plan de plateforme/infra l'appelle en shell)" _m29o_e10_runner
check_cmd "plateforme/k8s : dernier pipeline de main réussi, avec un job validation" _m29o_pipeline_main_ok plateforme/k8s '^validation'
check_cmd "plateforme/gitops : dernier pipeline de main réussi, avec un job validation" _m29o_pipeline_main_ok plateforme/gitops '^validation'
check_cmd "plateforme/infra : dernier pipeline de main réussi" _m29o_pipeline_main_ok plateforme/infra
check_cmd "plateforme/politiques : dernier pipeline de main réussi, règles Rego testées" _m29o_pipeline_main_ok plateforme/politiques 'rego'
