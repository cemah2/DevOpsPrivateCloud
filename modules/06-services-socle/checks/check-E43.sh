# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E43.sh — M06-E43 « Astreinte : les services socle en panne » : tout le périmètre de
# M06-E35 à M06-E42 est sain, aucune panne n'est encore active, et le post-mortem est rédigé.
# Lecture seule.
# shellcheck disable=SC2016  # les scripts bash -c reçoivent le chemin en argument ($1)

title "M06-E43 — Astreinte : les services socle en panne"

_m06_e43_pm="${WB_DEPOT:-$HOME/medisphere}/docs/socle/post-mortems"
check_cmd "post-mortem rédigé (docs/socle/post-mortems/*INC-3350*.md)" \
  bash -c 'ls "$1"/*INC-3350*.md >/dev/null 2>&1' _ "$_m06_e43_pm"
check_output "post-mortem : chronologie présente" '^#+ .*[Cc]hronologie' \
  bash -c 'cat "$1"/*INC-3350*.md 2>/dev/null' _ "$_m06_e43_pm"
check_output "post-mortem : causes racines présentes" '^#+ .*[Cc]auses?' \
  bash -c 'cat "$1"/*INC-3350*.md 2>/dev/null' _ "$_m06_e43_pm"
check_output "post-mortem : détection analysée" '^#+ .*[Dd][ée]tection' \
  bash -c 'cat "$1"/*INC-3350*.md 2>/dev/null' _ "$_m06_e43_pm"
check_output "post-mortem : actions présentes" '^#+ .*[Aa]ctions' \
  bash -c 'cat "$1"/*INC-3350*.md 2>/dev/null' _ "$_m06_e43_pm"
check_cmd "post-mortem : commité dans le dépôt de documentation" \
  bash -c 'cd "$1" && f=$(ls ./*INC-3350*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && git ls-files --error-unmatch "$f" >/dev/null 2>&1 && [ -z "$(git status --porcelain -- "$f")" ]' _ "$_m06_e43_pm"
check_cmd "aucune panne M06 encore marquée active (lab/bin/break)" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M06-E* >/dev/null 2>&1'

_m06_e43_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E35.sh
source "$_m06_e43_checks/check-E35.sh"
# shellcheck source=check-E36.sh
source "$_m06_e43_checks/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m06_e43_checks/check-E37.sh"
# shellcheck source=check-E38.sh
source "$_m06_e43_checks/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_m06_e43_checks/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_m06_e43_checks/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_m06_e43_checks/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_m06_e43_checks/check-E42.sh"
