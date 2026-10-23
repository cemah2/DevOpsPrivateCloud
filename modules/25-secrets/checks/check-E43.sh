# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes bash -c entre apostrophes
#
# check-E43.sh — M25-E43 « Astreinte : la nuit où le coffre s'est fermé » : aucune panne M25 encore
# active, post-mortem INC-5243 (chronologie, causes, extraits de diagnostic, section Détection, aucun
# secret), RB-255 « coffre fermé » sur main ; puis rejoue les contrôles de M25-E35 à M25-E42 présents.
# Lecture seule.

# shellcheck source=_m25-expert-b.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m25-expert-b.sh"

title "M25-E43 — Astreinte : la nuit où le coffre s'est fermé"
require_cmd curl jq

check_cmd "aucune panne M25 encore marquée active (astreinte close par --annuler)" _m25y_aucune_panne

_m25y_e43_pm="$(_m25y_post_mortem INC-5243)"
_m25y_e43_txt=""
[[ -n "$_m25y_e43_pm" ]] && _m25y_e43_txt="$(_m25p_fichier "$_M25P_DOC" "$_m25y_e43_pm" || true)"
check_cmd "post-mortem INC-5243 sur main (${_m25y_e43_pm:-introuvable})" test -n "$_m25y_e43_txt"
check_output "post-mortem : chronologie" '^#+ .*[Cc]hronologie' printf '%s\n' "$_m25y_e43_txt"
check_output "post-mortem : causes" '^#+ .*[Cc]auses?' printf '%s\n' "$_m25y_e43_txt"
check_output "post-mortem : section Détection" '^#+ .*[Dd][ée]tection' printf '%s\n' "$_m25y_e43_txt"
check_output "post-mortem : extraits de diagnostic (sys/health, seal-status, raft, journalctl, bao…)" \
  'sys/health|seal-status|list-peers|autopilot|journalctl|bao (read|token|policy|write|operator)' printf '%s\n' "$_m25y_e43_txt"
check_cmd "post-mortem : aucun jeton, aucune clé, aucun secret recopié" _m25y_sans_secret "$_m25y_e43_txt"

check_cmd "RB-255 « coffre fermé » sur main (kms01, quorum ou leader, scellé, VIP, dépositaires, gestes interdits)" \
  _m25p_doc "$_M25P_DOC" "$_M25P_RB" 'RB-255.*\.md$' 40 'kms01' '(quorum|leader)' 'scell' 'VIP' 'd[ée]positaire' '(jamais|interdit)'

_m25y_e43_dir="$(dirname "${BASH_SOURCE[0]}")"
for _m25y_e43_x in E35 E36 E37 E38 E39 E40 E41 E42; do
  # shellcheck disable=SC1090
  [[ -f "$_m25y_e43_dir/check-$_m25y_e43_x.sh" ]] && source "$_m25y_e43_dir/check-$_m25y_e43_x.sh"
done
