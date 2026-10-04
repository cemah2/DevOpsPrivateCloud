# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E30.sh — M01-E30 « Superviser GitLab : sondes de santé, services, journaux, métriques »
# Lancé depuis adm01. Lecture seule ; exécute ta sonde ~/lab-scripts/sonde-forge.sh
# (qui ne doit elle-même rien modifier).

title "M01-E30 — Superviser GitLab"
require_cmd curl jq ssh

_m01_get() { gitlab_api "$1" 2>/dev/null || true; }
_m01_URL="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_m01_SONDE="$HOME/lab-scripts/sonde-forge.sh"
_m01_JETON="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"

# --- 1. Sondes HTTP depuis adm01 ----------------------------------------------------------
check_http "adm01 lit /-/readiness?all=1 (liste d'adresses autorisées) : HTTP 200" "$_m01_URL/-/readiness?all=1" 200
check_output "/-/readiness?all=1 : toutes les dépendances « ok »" '^ok$' \
  bash -c 'curl -s --max-time 10 "$1" | jq -r "[to_entries[] | select(.value | type == \"array\") | .value[].status] | if length > 0 and all(. == \"ok\") then \"ok\" else \"ko\" end"' _ "$_m01_URL/-/readiness?all=1"
check_http "adm01 lit /-/liveness : HTTP 200" "$_m01_URL/-/liveness" 200

# --- 2. Métriques ----------------------------------------------------------------------------
check_output "métriques système de git01 exposées sur 10.10.20.12:9100 (format Prometheus)" '^node_memory_MemAvailable_bytes' \
  curl -s --max-time 5 http://10.10.20.12:9100/metrics
check_ssh "git01 : le serveur Prometheus embarqué n'est pas réactivé" git01 \
  '! sudo -n gitlab-ctl status prometheus 2>/dev/null | grep -q "^run:"'

# --- 3. Sonde ----------------------------------------------------------------------------------
check_cmd "sonde $_m01_SONDE présente et exécutable" test -x "$_m01_SONDE"
check_cmd "la sonde renvoie 0 sur une forge saine" "$_m01_SONDE"
check_cmd "la sonde n'affiche pas le jeton" \
  bash -c '[[ -r "$2" ]] && ! "$1" 2>&1 | grep -qF -- "$(<"$2")"' _ "$_m01_SONDE" "$_m01_JETON"
check_cmd "plateforme/medisphere : sonde versionnée sous forge/supervision/" \
  jq -e 'any(.[]?; .name | test("sonde"))' \
  <<<"$(_m01_get "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=forge%2Fsupervision&per_page=50")"
check_cmd "plateforme/medisphere : runbook RB-012 dans docs/socle/runbooks/" \
  jq -e 'any(.[]?; .name | startswith("RB-012"))' \
  <<<"$(_m01_get "projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=docs%2Fsocle%2Frunbooks&per_page=100")"
