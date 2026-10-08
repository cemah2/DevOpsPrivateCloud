# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent le chemin en argument ($1)
# check-E43.sh — M09-E43 « Astreinte : le cluster en détresse » : tout le périmètre de M09-E35 à
# M09-E42 est sain, aucune panne n'est encore active, et le post-mortem est rédigé. Lecture seule.

title "M09-E43 — Astreinte : le cluster en détresse"

_m09_e43_pm="${WB_DEPOT:-$HOME/medisphere}/docs/virtualisation/post-mortems"
check_cmd "post-mortem rédigé (docs/virtualisation/post-mortems/*INC-3650*.md)" \
  bash -c 'ls "$1"/*INC-3650*.md >/dev/null 2>&1' _ "$_m09_e43_pm"
for _m09_e43_s in '[Cc]hronologie' '[Cc]auses?' '[Dd][ée]tection' '[Aa]ctions'; do
  check_output "post-mortem : section ${_m09_e43_s//[\[\]]/} présente" "^#+ .*${_m09_e43_s}" \
    bash -c 'cat "$1"/*INC-3650*.md 2>/dev/null' _ "$_m09_e43_pm"
done
check_cmd "post-mortem : commité dans le dépôt de documentation" \
  bash -c 'cd "$1" && f=$(ls ./*INC-3650*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && git ls-files --error-unmatch "$f" >/dev/null 2>&1 && [ -z "$(git status --porcelain -- "$f")" ]' _ "$_m09_e43_pm"
check_cmd "aucune panne M09 encore marquée active (lab/bin/break)" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M09-E* >/dev/null 2>&1'

_m09_e43_checks="$(dirname "${BASH_SOURCE[0]}")"
# Les runbooks RB-093/RB-094 et la clôture des pannes sont contrôlés aussi par les checks d'origine.
# shellcheck source=check-E35.sh
source "$_m09_e43_checks/check-E35.sh"
# shellcheck source=check-E36.sh
source "$_m09_e43_checks/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m09_e43_checks/check-E37.sh"
# shellcheck source=check-E38.sh
source "$_m09_e43_checks/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_m09_e43_checks/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_m09_e43_checks/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_m09_e43_checks/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_m09_e43_checks/check-E42.sh"
