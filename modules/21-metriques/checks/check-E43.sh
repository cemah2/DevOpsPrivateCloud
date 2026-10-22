# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent le chemin en argument ($1)
# check-E43.sh — M21-E43 « Astreinte : une nuit agitée » : tout le périmètre de M21-E35 à M21-E42 est
# sain, aucune panne n'est encore active, le post-mortem est rédigé et commité. Lecture seule.

title "M21-E43 — Astreinte : une nuit agitée"

_m21_e43_pm="${WB_DEPOT:-$HOME/medisphere}/docs/kubernetes/post-mortems"
check_cmd "post-mortem rédigé (docs/kubernetes/post-mortems/*INC-4843*.md)" \
  bash -c 'ls "$1"/*INC-4843*.md >/dev/null 2>&1' _ "$_m21_e43_pm"
check_output "post-mortem : chronologie présente" '^#+ .*[Cc]hronologie' \
  bash -c 'cat "$1"/*INC-4843*.md 2>/dev/null' _ "$_m21_e43_pm"
check_output "post-mortem : causes racines présentes" '^#+ .*[Cc]auses?' \
  bash -c 'cat "$1"/*INC-4843*.md 2>/dev/null' _ "$_m21_e43_pm"
check_output "post-mortem : détection analysée (qu'est-ce qui surveillait la supervision ?)" '^#+ .*[Dd][ée]tection' \
  bash -c 'cat "$1"/*INC-4843*.md 2>/dev/null' _ "$_m21_e43_pm"
check_output "post-mortem : actions présentes" '^#+ .*[Aa]ctions' \
  bash -c 'cat "$1"/*INC-4843*.md 2>/dev/null' _ "$_m21_e43_pm"
check_output "post-mortem : extraits de diagnostic (PromQL, amtool, API, journalctl, kubectl)" \
  'up\{|amtool|/api/v[12]/|journalctl|kubectl (get|describe|logs)|promtool' \
  bash -c 'cat "$1"/*INC-4843*.md 2>/dev/null' _ "$_m21_e43_pm"
check_cmd "post-mortem : aucun secret recopié (clé, jeton, mot de passe SMTP ou S3)" \
  bash -c 'ls "$1"/*INC-4843*.md >/dev/null 2>&1 && ! cat "$1"/*INC-4843*.md 2>/dev/null | grep -Eqi "PRIVATE KEY|glpat-|eyJhbGciOi|secret_key:[[:space:]]*[^[:space:]<]|auth_password:[[:space:]]*[^[:space:]<]"' _ "$_m21_e43_pm"
check_cmd "post-mortem : commité dans le dépôt de documentation" \
  bash -c 'cd "$1" && f=$(ls ./*INC-4843*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && git ls-files --error-unmatch "$f" >/dev/null 2>&1 && [ -z "$(git status --porcelain -- "$f")" ]' _ "$_m21_e43_pm"
check_cmd "aucune panne M21 encore marquée active (lab/bin/break)" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M21-E* >/dev/null 2>&1'

_m21_e43_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E35.sh
source "$_m21_e43_checks/check-E35.sh"
# shellcheck source=check-E36.sh
source "$_m21_e43_checks/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m21_e43_checks/check-E37.sh"
# shellcheck source=check-E38.sh
source "$_m21_e43_checks/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_m21_e43_checks/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_m21_e43_checks/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_m21_e43_checks/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_m21_e43_checks/check-E42.sh"
