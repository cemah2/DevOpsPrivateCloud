# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes et filtres jq entre apostrophes
#
# check-E13.sh — M26-E13 : confiner un service (AppArmor sur mon01, SELinux sur les hôtes Rocky).
# À lancer depuis adm01. Lecture seule : SSH de consultation (aa-status par « sudo -n », getenforce),
# ports de Mailpit, GitLab, ~/m26/e13.

# shellcheck source=_m26-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-operationnel.sh"

title "M26-E13 — Confiner un service : AppArmor et SELinux"
require_cmd jq curl ssh

_m26o_e13_mon="${WB_M21_MON01:-mon01}"
_m26o_e13_aa="$(remote "$_m26o_e13_mon" 'sudo -n aa-status --json' 2>/dev/null || true)"
check_cmd "$_m26o_e13_mon : profil AppArmor « mailpit » chargé en enforce" \
  _m26o_json "$_m26o_e13_aa" '.profiles.mailpit == "enforce"'
check_cmd "$_m26o_e13_mon : le processus de Mailpit est confiné par ce profil" \
  _m26o_json "$_m26o_e13_aa" '[.processes // {} | to_entries[] | select(.key | test("mailpit")) | .value[] | .profile] | any(. == "mailpit")'
check_ssh "$_m26o_e13_mon : Mailpit actif" "$_m26o_e13_mon" 'systemctl is-active --quiet mailpit'
check_port "Mailpit reçoit toujours (SMTP 25 sur mon01)" "$_m26o_e13_mon.par1.medisphere.internal" 25
check_port "Mailpit répond toujours (API 8025 sur mon01)" "$_m26o_e13_mon.par1.medisphere.internal" 8025

check_cmd "plateforme/ansible : host_vars/mon01/durcissement.yml impose le mode enforce" \
  _m26o_contient "$_M26O_P_ANSIBLE" inventories/lab/host_vars/mon01/durcissement.yml '^[[:space:]]*mode:[[:space:]]*enforce'
check_cmd "plateforme/ansible : gabarit du profil AppArmor de Mailpit dans le rôle" \
  _m26o_fichier "$_M26O_P_ANSIBLE" roles/durcissement/templates/apparmor/usr.local.bin.mailpit.j2

_m26o_e13_rocky=(ipa01 "${_M26O_TEMOIN_ROCKY}")
_m26o_joignable "$_M26O_ROCKY" && _m26o_e13_rocky+=("$_M26O_ROCKY")
for _m26o_e13_h in "${_m26o_e13_rocky[@]}"; do
  check_ssh_output "$_m26o_e13_h : SELinux en enforcing (mode courant)" "$_m26o_e13_h" '^Enforcing$' 'getenforce'
  check_ssh "$_m26o_e13_h : SELinux enforcing au démarrage, politique targeted" "$_m26o_e13_h" \
    'grep -Eq "^SELINUX=enforcing" /etc/selinux/config && grep -Eq "^SELINUXTYPE=targeted" /etc/selinux/config'
done

check_cmd "travail ~/m26/e13/journal-mac.md : décisions d'aa-logprof et analyse d'un refus SELinux" bash -c \
  'f="$1"; [[ -s "$f" ]] && grep -Eqi "logprof" "$f" && grep -Eqi "avc|audit2why" "$f" && grep -Eqi "restorecon|contexte" "$f"' _ \
  "$_M26O_TRAVAIL/e13/journal-mac.md"
