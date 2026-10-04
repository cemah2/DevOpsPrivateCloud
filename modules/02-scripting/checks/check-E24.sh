# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E24.sh — M02-E24 : CI du projet outils : lint et tests sur runner01
# À lancer depuis adm01. Lecture seule : outils de runner01 (SSH) et API GitLab
# (jeton des checks, read_api) : dernier pipeline de main, jobs, rapports de tests.

title "M02-E24 — CI du projet outils : lint et tests sur runner01"
require_cmd jq curl ssh

_m02_p="projects/plateforme%2Foutils"
_m02_val() { jq -r "$2" <<<"$1" 2>/dev/null || true; }

# --- Outils de runner01, tels que les voit le compte gitlab-runner -------------------
_m02_outil() { remote runner01 "sudo -n -u gitlab-runner -H bash -lc '$1' 2>&1"; }
check_output "runner01 : ShellCheck 0.11 pour gitlab-runner" '^version: 0\.11\.' _m02_outil 'shellcheck --version'
check_output "runner01 : shfmt 3.14 pour gitlab-runner" '^v?3\.14\.' _m02_outil 'shfmt --version'
check_output "runner01 : jq 1.8 pour gitlab-runner" '^jq-1\.8\.' _m02_outil 'jq --version'
check_output "runner01 : bats-core 1.13 pour gitlab-runner" '^Bats 1\.13\.' _m02_outil 'bats --version'
check_output "runner01 : Task 3.x pour gitlab-runner" '(^|[^0-9])3\.[0-9]+\.[0-9]+' _m02_outil 'task --version'
check_output "runner01 : uv pour gitlab-runner" '^uv 0\.' _m02_outil 'uv --version'

# --- Configuration CI de main ------------------------------------------------------
_m02_ci="$(gitlab_api "$_m02_p/repository/files/.gitlab-ci.yml/raw?ref=main" 2>/dev/null)" || _m02_ci=""
check_output ".gitlab-ci.yml de main déclare un rapport JUnit" 'junit:' printf '%s\n' "$_m02_ci"
check_cmd "aucun secret Proxmox (PVE_TOKEN_SECRET) dans .gitlab-ci.yml" \
  bash -c '[[ -n "$1" ]] && ! grep -q "PVE_TOKEN_SECRET" <<<"$1"' _ "$_m02_ci"
if _m02_vars="$(gitlab_api "$_m02_p/variables" 2>/dev/null)"; then
  check_output "aucune variable CI PVE_* dans le projet (les tests ne joignent pas Proxmox)" '^0$' \
    _m02_val "$_m02_vars" '[.[] | select(.key | startswith("PVE_"))] | length'
else
  skip "variables CI du projet" "illisibles avec le jeton des checks"
fi
_m02_projet="$(gitlab_api "$_m02_p" 2>/dev/null)" || _m02_projet=""
check_output "fusion refusée tant que le pipeline n'a pas réussi" '^true$' \
  _m02_val "$_m02_projet" '.only_allow_merge_if_pipeline_succeeds'

# --- Dernier pipeline réussi de main ------------------------------------------------
_m02_pl="$(gitlab_api "$_m02_p/pipelines?ref=main&status=success&per_page=1" 2>/dev/null)" || _m02_pl="[]"
_m02_pid="$(_m02_val "$_m02_pl" '.[0].id // empty')"
check_cmd "main a au moins un pipeline réussi" test -n "$_m02_pid"
if [[ -n "$_m02_pid" ]]; then
  _m02_jobs="$(gitlab_api "$_m02_p/pipelines/$_m02_pid/jobs?per_page=100" 2>/dev/null)" || _m02_jobs="[]"
  for _m02_j in shellcheck ruff bats pytest build; do
    check_output "dernier pipeline réussi de main : job $_m02_j réussi" '^true$' \
      _m02_val "$_m02_jobs" "any(.[]; .name == \"$_m02_j\" and .status == \"success\")"
  done
  check_output "les jobs du projet tournent sur un runner « shell »" '^true$' \
    _m02_val "$_m02_jobs" '[.[] | select(.name == "bats" or .name == "pytest")] | length > 0 and all(.[]; .tag_list | index("shell"))'
  _m02_tr="$(gitlab_api "$_m02_p/pipelines/$_m02_pid/test_report_summary" 2>/dev/null)" || _m02_tr=""
  check_output "rapport de tests du pipeline : des tests bats ET pytest remontés" '^true$' \
    _m02_val "$_m02_tr" '([.test_suites[] | select(.name == "bats") | .total_count] | add // 0) > 0
      and ([.test_suites[] | select(.name == "pytest") | .total_count] | add // 0) > 0'
  check_output "rapport de tests du pipeline : aucun échec" '^0$' \
    _m02_val "$_m02_tr" '(.total.failed // 0) + (.total.error // 0)'
  check_output "le job build a archivé un paquet (artefacts)" '^true$' \
    _m02_val "$_m02_jobs" 'any(.[]; .name == "build" and ((.artifacts // []) | length > 0))'
fi
