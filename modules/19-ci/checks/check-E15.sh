# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E15.sh — M19-E15 : Semgrep CE et Gitleaks dans le composant securite
# À lancer depuis adm01. Lecture seule : API GitLab (pipelines, jobs, artefacts, fichiers).

# shellcheck source=_m19-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-operationnel.sh"

title "M19-E15 — Semgrep CE et Gitleaks dans le composant securite"
require_cmd jq yq curl

_m19o_e15_main="$(_m19o_pipeline "$_M19O_P_API" "ref=main")"
_m19o_e15_jobs="$(_m19o_jobs "$_M19O_P_API" "$(jq -r '.id // 0' <<<"${_m19o_e15_main:-null}" 2>/dev/null || echo 0)")"
for _m19o_e15_j in securite:semgrep securite:gitleaks; do
  check_cmd "mediagenda/api : $_m19o_e15_j a réussi dans le dernier pipeline de main" \
    _m19o_json "$_m19o_e15_jobs" 'any(.[]; .name == $j and .status == "success")' --arg j "$_m19o_e15_j"
done
check_cmd "securite:semgrep a publié un rapport SAST (artefact sast)" \
  _m19o_json "$_m19o_e15_jobs" 'any(.[]; .name == "securite:semgrep" and any(.artifacts[]?; .file_type == "sast"))'
check_cmd "securite:gitleaks a publié son rapport (JUnit)" \
  _m19o_json "$_m19o_e15_jobs" 'any(.[]; .name == "securite:gitleaks" and any(.artifacts[]?; .file_type == "junit"))'

_m19o_e15_ci="$(_m19o_contenu "$_M19O_P_API" .gitlab-ci.yml)"
check_cmd "mediagenda/api (main) : n'inclut plus le gabarit v1 qualite.yml (Gitleaks dans le composant securite)" \
  bash -c '[[ -n "$1" ]] && ! grep -q "qualite.yml" <<<"$1"' _ "$_m19o_e15_ci"
_m19o_e15_v="$(_m19o_version_composant "$_m19o_e15_ci" securite)"
_m19o_e15_tpl="$(_m19o_contenu "$_M19O_P_TPL" templates/securite/template.yml "${_m19o_e15_v:-main}")"
_m19o_e15_epingle() { # CONTENU_PROJET CONTENU_COMPOSANT NOM MOTIF_VERSION
  local s
  s="$(yq -r ".include[] | select(.component | test(\"/securite@\")) | .inputs.image_$3 // \"\"" <<<"$1" 2>/dev/null || true)"
  if [[ -n "$s" ]]; then grep -qE "$4@sha256:[a-f0-9]{64}$" <<<"$s"; else grep -qE "$4@sha256:[a-f0-9]{64}" <<<"$2"; fi
}
check_cmd "image Semgrep CE 1.18x épinglée par empreinte (composant securite ${_m19o_e15_v:-?})" \
  _m19o_e15_epingle "$_m19o_e15_ci" "$_m19o_e15_tpl" semgrep 'semgrep/semgrep:1\.18[0-9]\.[0-9]+(-nonroot)?'
check_cmd "image Gitleaks 8.30.x épinglée par empreinte" \
  _m19o_e15_epingle "$_m19o_e15_ci" "$_m19o_e15_tpl" gitleaks 'gitleaks/gitleaks:v8\.30\.[0-9]+'
check_output "normes-pipeline.md (main) : politique d'exception (nosemgrep, .trivyignore, .gitleaksignore)" 'nosemgrep' \
  _m19o_contenu "$_M19O_P_DOC" docs/livraison/ci/normes-pipeline.md
