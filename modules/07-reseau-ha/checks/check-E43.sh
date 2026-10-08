# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
# check-E43.sh — M07-E43 « Astreinte : la bordure en panne » : bordure redondante et prête à basculer,
# tout le périmètre de M07-E35 à M07-E42 sain, aucune panne encore active, post-mortem rédigé.
# Lecture seule.

# shellcheck source=_m07-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-expert.sh"

title "M07-E43 — Astreinte : la bordure en panne"
require_cmd ssh jq git

_m07_e43_pm="${WB_DEPOT:-$HOME/medisphere}/docs/socle/post-mortems"
check_cmd "post-mortem rédigé (docs/socle/post-mortems/*INC-3410*.md)" \
  bash -c 'ls "$1"/*INC-3410*.md >/dev/null 2>&1' _ "$_m07_e43_pm"
for _m07_e43_s in chronologie:'[Cc]hronologie' causes:'[Cc]auses?' 'détection:[Dd][ée]tection' actions:'[Aa]ctions'; do
  check_output "post-mortem : section ${_m07_e43_s%%:*}" "^#+ .*${_m07_e43_s#*:}" \
    bash -c 'cat "$1"/*INC-3410*.md 2>/dev/null' _ "$_m07_e43_pm"
done
check_cmd "post-mortem : commité dans le dépôt de documentation" \
  bash -c 'cd "$1" && f=$(ls ./*INC-3410*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && git ls-files --error-unmatch "$f" >/dev/null 2>&1 && [ -z "$(git status --porcelain -- "$f")" ]' _ "$_m07_e43_pm"
check_cmd "aucune panne M07 encore marquée active (lab/bin/break)" _m07x_aucune_panne_active

# La bordure est prête à basculer : keepalived (et conntrackd s'il est installé) actifs et activés
# sur les deux passerelles, un seul maître.
for _m07_e43_gw in gw01 gw02; do
  check_cmd "$_m07_e43_gw : keepalived actif et activé au démarrage" _m07x_ok "$_m07_e43_gw" \
    'systemctl is-active -q keepalived && systemctl is-enabled -q keepalived'
  check_cmd "$_m07_e43_gw : conntrackd actif et activé (s'il est installé)" _m07x_ok "$_m07_e43_gw" \
    '! systemctl cat conntrackd >/dev/null 2>&1 || { systemctl is-active -q conntrackd && systemctl is-enabled -q conntrackd; }'
done
check_cmd "bordure : la VIP 10.10.10.1 est portée par une seule passerelle" _m07x_un_seul_maitre gw01 gw02 10.10.10.1

_m07_e43_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E35.sh
source "$_m07_e43_checks/check-E35.sh"
# shellcheck source=check-E36.sh
source "$_m07_e43_checks/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m07_e43_checks/check-E37.sh"
# shellcheck source=check-E38.sh
source "$_m07_e43_checks/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_m07_e43_checks/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_m07_e43_checks/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_m07_e43_checks/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_m07_e43_checks/check-E42.sh"
