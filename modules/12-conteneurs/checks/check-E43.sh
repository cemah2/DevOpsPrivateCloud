# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les scripts bash -c reçoivent le chemin en argument ($1)
# check-E43.sh — M12-E43 « Astreinte : la pile de recette est en panne » : tout le périmètre de la
# pile de recette (contrôles de M12-E35, E36, E37, E39 et E41) est sain, aucune panne M12 n'est
# encore active, le post-mortem INC-3950 est rédigé et commité. Lecture seule. Durée : 3 à 4 minutes.

title "M12-E43 — Astreinte : la pile de recette est en panne"

_m12_e43_pm="${WB_DEPOT:-$HOME/medisphere}/docs/socle/post-mortems"
check_cmd "post-mortem rédigé (docs/socle/post-mortems/*INC-3950*.md)" \
  bash -c 'ls "$1"/*INC-3950*.md >/dev/null 2>&1' _ "$_m12_e43_pm"
for _m12_e43_s in "chronologie|[Cc]hronologie" "causes racines|[Cc]auses?" "détection|[Dd][ée]tection" "actions|[Aa]ctions"; do
  check_output "post-mortem : section ${_m12_e43_s%%|*} présente" "^#+ .*${_m12_e43_s#*|}" \
    bash -c 'cat "$1"/*INC-3950*.md 2>/dev/null' _ "$_m12_e43_pm"
done
check_output "post-mortem : trois causes distinctes identifiées (au moins trois éléments sous « Causes »)" '^ok$' \
  bash -c 'awk "/^#+ .*[Cc]ause/{f=1;next} /^#+ /{f=0} f && /^[[:space:]]*([-*]|[0-9]+\\.) /{n++} END{print (n>=3)?\"ok\":\"non\"}" "$1"/*INC-3950*.md 2>/dev/null' _ "$_m12_e43_pm"
check_output "post-mortem : sorties de diagnostic citées (docker inspect, events, logs, df…)" \
  'docker (inspect|events|logs|compose (ps|config|logs))|df -h|system df|nft list' \
  bash -c 'cat "$1"/*INC-3950*.md 2>/dev/null' _ "$_m12_e43_pm"
check_cmd "post-mortem : commité dans le dépôt de documentation" \
  bash -c 'cd "$1" && f=$(ls ./*INC-3950*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && git ls-files --error-unmatch "$f" >/dev/null 2>&1 && [ -z "$(git status --porcelain -- "$f")" ]' _ "$_m12_e43_pm"
check_cmd "aucune panne M12 encore marquée active (lab/bin/break)" \
  bash -c '! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M12-E* >/dev/null 2>&1'

_m12_e43_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E35.sh
source "$_m12_e43_checks/check-E35.sh"
# shellcheck source=check-E36.sh
source "$_m12_e43_checks/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m12_e43_checks/check-E37.sh"
# shellcheck source=check-E39.sh
source "$_m12_e43_checks/check-E39.sh"
# shellcheck source=check-E41.sh
source "$_m12_e43_checks/check-E41.sh"
