# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E38.sh — M26-E38 « sudo cassé » : « sudo -n » du compte d'automatisation admin fonctionne de
# nouveau sur les VMs non critiques, sans dérogation dangereuse (pas de requiretty, drop-ins bien
# protégés), panne close. Lecture seule (sauf « sudo -n true » qui est le test lui-même).
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E38 — sudo du compte d'automatisation rétabli"
require_cmd ssh

_m26_e38_vms="${WB_M26_VMS_SUDO:-nbx01 dns02 mon01}"
for vm in $_m26_e38_vms; do
  # SSH répond mais « sudo -n » non : c'est précisément la panne, le contrôle doit être ROUGE (pas sauté).
  if ! _m26x_ssh_ok "$vm" && remote "$vm" true </dev/null >/dev/null 2>&1; then
    check_ssh "$vm : « sudo -n true » fonctionne (Ansible et checks)" "$vm" "sudo -n true"
  elif _m26x_ssh_ok "$vm"; then
    check_ssh "$vm : « sudo -n true » fonctionne (Ansible et checks)" "$vm" "sudo -n true"
    check_ssh "$vm : aucun « Defaults requiretty » dans sudoers" "$vm" \
      "! sudo -n grep -RqsE '^[[:space:]]*Defaults[[:space:]]+requiretty' /etc/sudoers /etc/sudoers.d/"
    check_ssh "$vm : aucun drop-in sudoers inscriptible par le groupe ou les autres" "$vm" \
      "! sudo -n find /etc/sudoers.d -maxdepth 1 -type f -perm /0022 | grep -q ."
    check_ssh_output "$vm : syntaxe sudoers valide" "$vm" 'parsed OK|parsed okay|^/etc/sudoers.* parsed' "sudo -n visudo -c"
  else
    skip "$vm" "SSH + sudo -n impossible depuis ce poste (ou VM éteinte)"
  fi
done
check_cmd "panne M26-E38 close" _m26x_aucune_panne_active E38
