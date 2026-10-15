# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E43.sh — M16-E43 « Astreinte : les données de MédiAgenda sont en danger » : tout le
# périmètre des pannes M16-E35 à E42 est sain, et le post-mortem INC-4350 est publié (branche main
# de plateforme/medisphere). Lecture seule.

# shellcheck source=_m16-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m16-expert.sh"

title "M16-E43 — Astreinte : post-mortem"
require_cmd kubectl jq ssh curl
_m16_e43_pm="$(_m16x_arbre plateforme/medisphere docs/socle/post-mortems | grep -- 'INC-4350' | head -n1)"
check_cmd "post-mortem INC-4350 publié (docs/socle/post-mortems/, branche main)" test -n "$_m16_e43_pm"
check_cmd "post-mortem : chronologie, causes racines, actions" _m16x_doc_main "${_m16_e43_pm:-absent}" \
  '^#+ .*chronologie' '^#+ .*causes?' '^#+ .*actions'
check_cmd "astreinte close (lab/bin/break 16 43 --annuler après réparation)" _m16x_aucune_panne_active E43

_m16_e43_dir="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E35.sh
source "$_m16_e43_dir/check-E35.sh"
# shellcheck source=check-E36.sh
source "$_m16_e43_dir/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m16_e43_dir/check-E37.sh"
# shellcheck source=check-E38.sh
source "$_m16_e43_dir/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_m16_e43_dir/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_m16_e43_dir/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_m16_e43_dir/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_m16_e43_dir/check-E42.sh"
