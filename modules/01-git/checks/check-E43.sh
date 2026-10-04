# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent le chemin en argument ($1)
#
# check-E43.sh — M01-E43 « Astreinte : la forge en difficulté »
# Post-mortem rédigé et publié, puis tout le périmètre de M01-E36 à M01-E42 sain (les dépôts
# d'exercice de E41 et E42 ne sont contrôlés que s'ils existent). Lecture seule.

title "M01-E43 — Astreinte : la forge en difficulté"
require_cmd git jq curl ssh

_m01_depot="${WB_DEPOT:-$HOME/medisphere}"
_m01_pm="$_m01_depot/docs/socle/post-mortems"
_m01_pm_lire() { cat "$_m01_pm"/*INC-2788*.md 2>/dev/null; }

check_cmd "post-mortem rédigé (docs/socle/post-mortems/*-INC-2788.md)" \
  bash -c 'ls "$1"/*INC-2788*.md >/dev/null 2>&1' _ "$_m01_pm"
check_output "post-mortem : chronologie" '^#+ .*[Cc]hronologie' _m01_pm_lire
check_output "post-mortem : causes racines" '^#+ .*[Cc]auses?' _m01_pm_lire
check_output "post-mortem : détection" '^#+ .*[Dd]étection' _m01_pm_lire
check_output "post-mortem : actions" '^#+ .*[Aa]ctions' _m01_pm_lire
_m01_pm_publie() {
  local f
  f="$(cd "$_m01_depot" 2>/dev/null && find docs/socle/post-mortems -maxdepth 1 -name '*INC-2788*.md' 2>/dev/null | sort | head -n 1)" || return 1
  [[ -n "$f" ]] || return 1
  gitlab_api "projects/plateforme%2Fmedisphere/repository/files/$(jq -rn --arg f "$f" '$f|@uri')?ref=main" >/dev/null 2>&1
}
check_cmd "post-mortem publié sur la branche main de plateforme/medisphere (fusionné par MR)" _m01_pm_publie
check_cmd "aucune panne M01-E36 à E43 encore marquée active" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M01-E3[6-9] \
             "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M01-E4[0-3] >/dev/null 2>&1'

_m01_astreinte=1
_m01_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E36.sh
source "$_m01_checks/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m01_checks/check-E37.sh"
# shellcheck source=check-E38.sh
source "$_m01_checks/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_m01_checks/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_m01_checks/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_m01_checks/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_m01_checks/check-E42.sh"
unset _m01_astreinte
