# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c
#
# check-E20.sh — M05-E20 : Qualité du code, fmt, validate, tflint, terraform-docs
# Lecture seule : outils de adm01, copies de travail ~/src/infra et ~/src/tofu-modules (tflint,
# fmt -check et terraform-docs --output-check ne modifient rien), pipelines sur la forge.

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E20 — Qualité du code : fmt, validate, tflint, terraform-docs"
require_cmd tofu git jq curl

check_output "adm01 : tflint 0.64.x installé" 'TFLint version 0\.64\.' tflint --version
check_output "adm01 : terraform-docs 0.24.x installé" 'v0\.24\.' terraform-docs --version

for _m05o_r in "$_m05o_infra" "$_m05o_modules"; do
  _m05o_n="${_m05o_r##*/}"
  check_cmd "$_m05o_n : .tflint.hcl présent" test -s "$_m05o_r/.tflint.hcl"
  check_cmd "$_m05o_n : hooks pre-commit tofu fmt, validate, tflint et terraform-docs" \
    bash -c 'f="$1/.pre-commit-config.yaml"; grep -q "tofu fmt" "$f" && grep -qi "validate" "$f" && grep -q "tflint" "$f" && grep -q "terraform-docs" "$f"' _ "$_m05o_r"
  check_cmd "$_m05o_n : hooks installés dans la copie de travail (pre-commit install)" \
    bash -c 'grep -qs "pre-commit" "$(git -C "$1" rev-parse --git-path hooks)/pre-commit"' _ "$_m05o_r"
  check_cmd "$_m05o_n : tofu fmt -check sans écart" bash -c 'cd "$1" && tofu fmt -check -recursive' _ "$_m05o_r"
  check_cmd "$_m05o_n : tflint sans avertissement (règles de .tflint.hcl)" \
    bash -c 'cd "$1" && tflint --recursive --config "$1/.tflint.hcl" --no-color' _ "$_m05o_r"
  check_cmd "$_m05o_n : documentation générée à jour (outils/docs-verifier.sh)" \
    bash -c 'cd "$1" && test -x outils/docs-verifier.sh && outils/docs-verifier.sh' _ "$_m05o_r"
done
check_cmd "infra : socle/README.md documenté par terraform-docs" \
  bash -c 'grep -q "BEGIN_TF_DOCS" "$1/socle/README.md"' _ "$_m05o_infra"
check_output "tflint : préréglage recommended du jeu de règles terraform" 'preset[[:space:]]*=[[:space:]]*"recommended"' \
  cat "$_m05o_infra/.tflint.hcl"
check_output "tflint : modules épinglés par étiquette (terraform_module_pinned_source)" 'terraform_module_pinned_source' \
  cat "$_m05o_infra/.tflint.hcl"

# --- CI : le dernier pipeline de main est vert --------------------------------------------------------
_m05o_dernier_pipeline() {
  gitlab_api "$(_m05o_projet "$1")/pipelines?ref=main&source=push&per_page=1" | jq -r '.[0].status // empty'
}
# « manual » : pipeline réussi dont les jobs apply manuels (E26) n'ont pas été lancés.
check_output "forge : dernier pipeline de main de plateforme/infra réussi" '^(success|manual)$' \
  _m05o_dernier_pipeline plateforme/infra
check_output "forge : dernier pipeline de main de plateforme/tofu-modules réussi" '^success$' \
  _m05o_dernier_pipeline plateforme/tofu-modules
