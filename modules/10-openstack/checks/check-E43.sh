# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E43.sh — M10-E43 « Astreinte : le cloud en détresse » : tout le périmètre de M10-E35 à
# M10-E42 est sain, aucune panne n'est encore active, le post-mortem et le runbook RB-103 sont
# rédigés et commités. Lecture seule.
# shellcheck disable=SC2016  # les scripts bash -c reçoivent le chemin en argument ($1)

# shellcheck source=_m10-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-expert.sh"

title "M10-E43 — Astreinte : le cloud en détresse"
require_cmd git

_m10_e43_pm="$_m10x_depot/docs/cloud/post-mortems"
check_cmd "post-mortem rédigé (docs/cloud/post-mortems/*INC-3750*.md)" \
  bash -c 'ls "$1"/*INC-3750*.md >/dev/null 2>&1' _ "$_m10_e43_pm"
for _m10_e43_s in 'chronologie:[Cc]hronologie' 'causes:[Cc]auses?' 'détection:[Dd][ée]tection' 'actions:[Aa]ctions'; do
  check_output "post-mortem : section ${_m10_e43_s%%:*} présente" "^#+ .*${_m10_e43_s#*:}" \
    bash -c 'cat "$1"/*INC-3750*.md 2>/dev/null' _ "$_m10_e43_pm"
done
check_cmd "post-mortem commité dans le dépôt de documentation" \
  bash -c 'cd "$1" && f=$(ls docs/cloud/post-mortems/*INC-3750*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && git ls-files --error-unmatch "$f" >/dev/null 2>&1 && [ -z "$(git status --porcelain -- "$f")" ]' _ "$_m10x_depot"
check_cmd "runbook RB-103 rédigé et commité (docs/cloud/runbooks/RB-103*.md)" \
  bash -c 'cd "$1" && f=$(ls docs/cloud/runbooks/RB-103*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && git ls-files --error-unmatch "$f" >/dev/null 2>&1 && [ -z "$(git status --porcelain -- "$f")" ]' _ "$_m10x_depot"
check_cmd "RB-103 : couvre No valid host, réseau, métadonnées, volumes et authentification" \
  bash -c 'f=$(ls "$1"/docs/cloud/runbooks/RB-103*.md 2>/dev/null | head -n 1); [ -n "$f" ] || exit 1
    for m in "No valid host" "IP flottante" "[Mm][ée]tadonn" "[Vv]olume" "[Jj]eton|[Aa]uthentif"; do grep -Eq "$m" "$f" || exit 1; done' _ "$_m10x_depot"
check_cmd "aucune panne M10 encore marquée active (lab/bin/break)" _m10x_aucune_panne_active

_m10_e43_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E35.sh
source "$_m10_e43_checks/check-E35.sh"
# shellcheck source=check-E36.sh
source "$_m10_e43_checks/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m10_e43_checks/check-E37.sh"
# shellcheck source=check-E38.sh
source "$_m10_e43_checks/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_m10_e43_checks/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_m10_e43_checks/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_m10_e43_checks/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_m10_e43_checks/check-E42.sh"
