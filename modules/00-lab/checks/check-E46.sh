# shellcheck shell=bash
# check-E46.sh — M00-E46 « Astreinte : pannes multiples » : tout le périmètre E38-E45 est sain,
# et le post-mortem est rédigé.
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent le chemin en argument ($1)
title "M00-E46 — Astreinte : pannes multiples"

_wb_depot="${WB_DEPOT:-$HOME/medisphere}"
_wb_pm="$_wb_depot/docs/socle/post-mortems"
check_cmd "post-mortem rédigé dans le dépôt (docs/socle/post-mortems/*-INC-2620.md)" \
  bash -c 'ls "$1"/*INC-2620*.md >/dev/null 2>&1' _ "$_wb_pm"
check_output "post-mortem : chronologie présente" '^#+ .*[Cc]hronologie' \
  bash -c 'cat "$1"/*INC-2620*.md 2>/dev/null' _ "$_wb_pm"
check_output "post-mortem : causes racines présentes" '^#+ .*[Cc]auses?' \
  bash -c 'cat "$1"/*INC-2620*.md 2>/dev/null' _ "$_wb_pm"
check_output "post-mortem : actions présentes" '^#+ .*[Aa]ctions' \
  bash -c 'cat "$1"/*INC-2620*.md 2>/dev/null' _ "$_wb_pm"

_wb_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E38.sh
source "$_wb_checks/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_wb_checks/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_wb_checks/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_wb_checks/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_wb_checks/check-E42.sh"
# shellcheck source=check-E43.sh
source "$_wb_checks/check-E43.sh"
# shellcheck source=check-E44.sh
source "$_wb_checks/check-E44.sh"
# shellcheck source=check-E45.sh
source "$_wb_checks/check-E45.sh"
