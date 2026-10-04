# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E43.sh — M02-E43 « Astreinte : l'outillage en panne » : tout le périmètre de M02-E35 à
# M02-E42 est sain, aucune panne n'est encore active, et le post-mortem est rédigé.
# Lecture seule.
# shellcheck disable=SC2016  # les scripts bash -c reçoivent le chemin en argument ($1)

title "M02-E43 — Astreinte : l'outillage en panne"

_m02_e43_pm="${WB_DEPOT:-$HOME/medisphere}/docs/socle/post-mortems"
check_cmd "post-mortem rédigé (docs/socle/post-mortems/*INC-2850*.md)" \
  bash -c 'ls "$1"/*INC-2850*.md >/dev/null 2>&1' _ "$_m02_e43_pm"
check_output "post-mortem : chronologie présente" '^#+ .*[Cc]hronologie' \
  bash -c 'cat "$1"/*INC-2850*.md 2>/dev/null' _ "$_m02_e43_pm"
check_output "post-mortem : causes racines présentes" '^#+ .*[Cc]auses?' \
  bash -c 'cat "$1"/*INC-2850*.md 2>/dev/null' _ "$_m02_e43_pm"
check_output "post-mortem : actions présentes" '^#+ .*[Aa]ctions' \
  bash -c 'cat "$1"/*INC-2850*.md 2>/dev/null' _ "$_m02_e43_pm"
check_cmd "post-mortem : commité dans le dépôt de documentation" \
  bash -c 'cd "$1" && f=$(ls ./*INC-2850*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && git ls-files --error-unmatch "$f" >/dev/null 2>&1 && [ -z "$(git status --porcelain -- "$f")" ]' _ "$_m02_e43_pm"
check_cmd "aucune panne M02 encore marquée active (lab/bin/break)" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M02-E* >/dev/null 2>&1'

_m02_e43_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E35.sh
source "$_m02_e43_checks/check-E35.sh"
# shellcheck source=check-E36.sh
source "$_m02_e43_checks/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m02_e43_checks/check-E37.sh"
# shellcheck source=check-E38.sh
source "$_m02_e43_checks/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_m02_e43_checks/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_m02_e43_checks/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_m02_e43_checks/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_m02_e43_checks/check-E42.sh"
