# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E43.sh — M15-E43 « Astreinte : plus rien n'entre dans le cluster » : tout le périmètre de
# M15-E35 à M15-E42 est sain, aucune panne n'est active, le post-mortem est rédigé et commité.
# Lecture seule.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

title "M15-E43 — Astreinte : plus rien n'entre dans le cluster"

_m15_e43_pm="$(cd "$_m15x_depot" 2>/dev/null && find docs/socle/post-mortems -maxdepth 1 -name "*INC-4250*.md" 2>/dev/null | sort | head -n 1)" || true
check_cmd "post-mortem rédigé (docs/socle/post-mortems/*INC-4250*.md)" test -n "$_m15_e43_pm"
if [[ -n "$_m15_e43_pm" ]]; then
  check_cmd "post-mortem : chronologie" _m15x_doc_contient "$_m15_e43_pm" '^#+ .*chronologie'
  check_cmd "post-mortem : causes racines" _m15x_doc_contient "$_m15_e43_pm" '^#+ .*cause'
  check_cmd "post-mortem : détection analysée" _m15x_doc_contient "$_m15_e43_pm" '^#+ .*d[ée]tection'
  check_cmd "post-mortem : actions correctives" _m15x_doc_contient "$_m15_e43_pm" '^#+ .*actions'
  check_cmd "post-mortem : preuves citées (hubble, cilium, vtysh, kubectl describe ou events)" \
    _m15x_doc_contient "$_m15_e43_pm" 'hubble observe|cilium(-dbg)? |vtysh|kubectl (describe|get events)'
  check_cmd "post-mortem : commité dans le dépôt de documentation" _m15x_doc_commite "$_m15_e43_pm"
fi
check_cmd "aucune panne M15 encore marquée active (lab/bin/break)" _m15x_aucune_panne_active

_m15_e43_checks="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=check-E35.sh
source "$_m15_e43_checks/check-E35.sh"
# shellcheck source=check-E36.sh
source "$_m15_e43_checks/check-E36.sh"
# shellcheck source=check-E37.sh
source "$_m15_e43_checks/check-E37.sh"
# shellcheck source=check-E38.sh
source "$_m15_e43_checks/check-E38.sh"
# shellcheck source=check-E39.sh
source "$_m15_e43_checks/check-E39.sh"
# shellcheck source=check-E40.sh
source "$_m15_e43_checks/check-E40.sh"
# shellcheck source=check-E41.sh
source "$_m15_e43_checks/check-E41.sh"
# shellcheck source=check-E42.sh
source "$_m15_e43_checks/check-E42.sh"
