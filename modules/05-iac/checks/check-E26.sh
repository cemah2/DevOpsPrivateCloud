# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E26.sh — M05-E26 « Pipeline IaC : plan en MR, apply protégé »
# .gitlab-ci.yml sur main (plans par configuration, applys manuels protégés, analyse de sécurité,
# empreinte de Trivy), variables protégées et masquées, branches protégées, un déploiement
# lab/socle réussi, un plan:socle réussi en MR, outils IaC de runner01 vus par gitlab-runner.

# shellcheck source=_m05-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-production.sh"

title "M05-E26 — Pipeline IaC"
require_cmd jq curl ssh

_m05_e26_ci=.gitlab-ci.yml

title "Pipeline (branche main)"
for _m05_e26_c in socle lab-m05 recette-m05; do
  check_cmd "jobs plan:$_m05_e26_c et apply:$_m05_e26_c" \
    _m05p_main_contient "$_m05_e26_ci" "^plan:$_m05_e26_c:" "^apply:$_m05_e26_c:"
done
check_cmd "apply : manuel" _m05p_main_contient "$_m05_e26_ci" 'when:[[:space:]]*manual'
check_cmd "apply : environnement lab/socle" _m05p_main_contient "$_m05_e26_ci" 'name:[[:space:]]*lab/socle'
check_cmd "apply : une seule exécution à la fois par état (resource_group)" _m05p_main_contient "$_m05_e26_ci" 'resource_group:'
check_cmd "apply : applique le plan enregistré (tofu apply … .tfplan)" _m05p_main_contient "$_m05_e26_ci" 'tofu apply[^#]*\.tfplan'
check_cmd "plan : lock en lecture seule et plan enregistré" \
  _m05p_main_contient "$_m05_e26_ci" '-lockfile=readonly' 'tofu plan[^#]*-out='
check_cmd "plan : rapport terraform pour le widget de la MR" _m05p_main_contient "$_m05_e26_ci" 'terraform:[[:space:]]*[^[:space:]]+\.json'
check_cmd "artefacts : accès restreint (developer, maintainer ou none)" \
  _m05p_main_contient "$_m05_e26_ci" 'access:[[:space:]]*"?(developer|maintainer|none)'
check_cmd "artefacts : aucun accès « all » explicite" _m05p_main_sans "$_m05_e26_ci" 'access:[[:space:]]*"?all'
check_cmd "analyse de sécurité : job securite et empreinte de Trivy" \
  _m05p_main_contient "$_m05_e26_ci" '^securite:' 'analyse-securite\.sh' 'sha256:[0-9a-f]{64}'
check_cmd "variable SKIP de E20 retirée" _m05p_main_sans "$_m05_e26_ci" '^[[:space:]]*SKIP:'

title "Secrets et protections (GitLab)"
check_cmd "PROXMOX_VE_API_TOKEN : protégée et masquée" \
  _m05p_variable_ok PROXMOX_VE_API_TOKEN '.protected and (.masked or (.masked_and_hidden // false))'
check_cmd "AWS_SECRET_ACCESS_KEY : protégée et masquée" \
  _m05p_variable_ok AWS_SECRET_ACCESS_KEY '.protected and (.masked or (.masked_and_hidden // false))'
_m05_e26_autres_variables() {
  _m05p_variable_ok PROXMOX_VE_ENDPOINT '.protected' && _m05p_variable_ok AWS_ACCESS_KEY_ID '.protected'
}
check_cmd "PROXMOX_VE_ENDPOINT et AWS_ACCESS_KEY_ID : protégées" _m05_e26_autres_variables
check_cmd "branche main protégée" _m05p_api_ok "$_M05P_PROJET/protected_branches" 'any(.[]; .name == "main")'
check_cmd "motif conf/* protégé" _m05p_api_ok "$_M05P_PROJET/protected_branches" 'any(.[]; .name == "conf/*")'

title "Exécutions"
check_cmd "environnement lab/socle : un déploiement réussi" \
  _m05p_api_ok "$_M05P_PROJET/deployments?environment=lab%2Fsocle&status=success&per_page=1" 'length > 0'
check_cmd "un pipeline de MR a exécuté plan:socle avec succès" \
  _m05p_job_dans_pipelines "source=merge_request_event&per_page=20" '^plan:socle$' '["success"]'
check_cmd "le job pre-commit (tofu fmt, validate, tflint…) a réussi sur main" \
  _m05p_job_dans_pipelines "ref=main&source=push&per_page=10" '^pre-commit$' '["success"]'

title "Outils de runner01 (vus par gitlab-runner)"
check_ssh_output "runner01 : OpenTofu 1.13" runner01 '^OpenTofu v1\.13\.' \
  'sudo -n -u gitlab-runner -H bash -lc "tofu version"'
check_ssh_output "runner01 : Terragrunt 1.x" runner01 '^terragrunt version v1\.' \
  'sudo -n -u gitlab-runner -H bash -lc "terragrunt --version"'
check_ssh_output "runner01 : Trivy 0.75.0" runner01 '^Version: 0\.75\.0$' \
  'sudo -n -u gitlab-runner -H bash -lc "trivy --version"'
check_ssh_output "runner01 : Checkov 3.3.x" runner01 '^3\.3\.' \
  'sudo -n -u gitlab-runner -H bash -lc "checkov --version"'
for _m05_e26_o in tflint terraform-docs jq aws; do
  check_ssh "runner01 : $_m05_e26_o visible par gitlab-runner" runner01 \
    "sudo -n -u gitlab-runner -H bash -lc 'command -v $_m05_e26_o'"
done
# L'empreinte attendue est celle écrite dans .gitlab-ci.yml (TRIVY_EMPREINTE).
_m05_e26_trivy_runner() {
  local attendu obtenu
  attendu="$(_m05p_contenu_main "$_m05_e26_ci" | grep -oE 'sha256:[0-9a-f]{64}' | head -n 1)"
  [[ -n "$attendu" ]] || return 1
  obtenu="$(remote runner01 'sha256sum "$(readlink -f "$(command -v trivy)")"' 2>/dev/null | cut -d' ' -f1)"
  [[ "sha256:$obtenu" == "$attendu" ]]
}
check_cmd "runner01 : le binaire trivy a l'empreinte écrite dans .gitlab-ci.yml" _m05_e26_trivy_runner
