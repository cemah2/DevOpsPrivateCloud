# shellcheck shell=bash
# shellcheck disable=SC2016  # motifs bash -c et filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E43.sh — M26-E43 « Astreinte : la semaine avant l'audit » : tout le périmètre M26-E35 à E42 sain,
# aucune panne active, dérive de conformité réparée, post-mortem et RB-265 rédigés. Rejoue les contrôles
# détaillés. Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E43 — Astreinte : la semaine avant l'audit"
require_cmd jq kubectl git ssh

_m26_e43_pm="$_m26x_depot/docs/kubernetes/post-mortems"
_e43_pm_cat() { cat "$_m26_e43_pm"/*INC-5343*.md 2>/dev/null; }
_e43_pm_present() { ls "$_m26_e43_pm"/*INC-5343*.md >/dev/null 2>&1; }
_e43_pm_sans_secret() { _e43_pm_present && ! _e43_pm_cat | grep -Eqi 'PRIVATE KEY|glpat-|eyJhbGciOi|BAO_SECRET|password:[[:space:]]*[^[:space:]<]'; }
_e43_aucune_panne() { ! ls "${XDG_STATE_HOME:-$HOME/.local/state}"/workbook/pannes-actives/M26-E* >/dev/null 2>&1; }
_e43_derive_reparee() {
  local vm
  for vm in ${WB_M26_VMS_SUDO:-nbx01 dns02 mon01} "${WB_M26_DERIVE_VM:-nbx01}"; do
    _m26x_ssh_ok "$vm" || continue
    _m26x_ssh "$vm" 'sshd -T 2>/dev/null' | grep -qi '^permitrootlogin yes' && return 1
  done
  return 0
}

check_cmd "post-mortem rédigé (docs/kubernetes/post-mortems/*INC-5343*.md)" _e43_pm_present
check_output "post-mortem : chronologie présente" '^#+ .*[Cc]hronologie' _e43_pm_cat
check_output "post-mortem : causes racines présentes" '^#+ .*[Cc]auses?' _e43_pm_cat
check_output "post-mortem : extraits de diagnostic (kubectl, nft, oscap, amtool, journalctl…)" \
  'kubectl (get|describe|logs)|nft |oscap|ssh-audit|journalctl|PolicyReport|hubble' _e43_pm_cat
check_cmd "post-mortem : aucun secret recopié" _e43_pm_sans_secret
check_cmd "RB-265 (semaine avant l'audit) rédigé et commité" \
  _m26x_doc_commite "docs/securite/durcissement/runbooks/RB-265-*.md"
check_cmd "dérive de conformité réparée sur les VMs échantillonnées" _e43_derive_reparee
check_cmd "aucune panne M26 encore marquée active" _e43_aucune_panne

_m26_e43_dir="$(dirname "${BASH_SOURCE[0]}")"
for _x in E35 E36 E37 E38 E39 E40 E41 E42; do
  # shellcheck disable=SC1090
  [ -f "$_m26_e43_dir/check-$_x.sh" ] && source "$_m26_e43_dir/check-$_x.sh"
done
