# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E39.sh — M26-E39 « service confiné » : Mailpit (mon01) et node_exporter (mon01, Rocky) tournent,
# MAC toujours actif (AppArmor enforce / SELinux enforcing), unités durcies mais fonctionnelles, panne
# close. Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E39 — Le service confiné démarre de nouveau"
require_cmd ssh

_m26_e39_mon="${WB_M26_MON01:-mon01}"
_m26_e39_rocky="${WB_M26_ROCKY:-ceph01}"
if _m26x_ssh_ok "$_m26_e39_mon"; then
  check_ssh "$_m26_e39_mon : Mailpit actif" "$_m26_e39_mon" \
    "u=\$(systemctl list-units --all --type=service --no-legend --plain | awk '/mailpit/{print \$1; exit}'); systemctl is-active \"\$u\" | grep -q '^active'"
  check_ssh "$_m26_e39_mon : node_exporter actif" "$_m26_e39_mon" \
    "u=\$(systemctl list-units --all --type=service --no-legend --plain | awk '/node_exporter/{print \$1; exit}'); systemctl is-active \"\$u\" | grep -q '^active'"
  check_ssh "$_m26_e39_mon : profil AppArmor de Mailpit toujours en enforce" "$_m26_e39_mon" \
    "sudo -n aa-status 2>/dev/null | grep -Eq 'mailpit.*(enforce)|^[[:space:]]*/usr/local/bin/mailpit' || sudo -n grep -Rqs mailpit /sys/kernel/security/apparmor/profiles 2>/dev/null"
else
  skip "$_m26_e39_mon" "SSH + sudo -n impossible"
fi
if _m26x_ssh_ok "$_m26_e39_rocky"; then
  check_ssh "$_m26_e39_rocky : SELinux toujours en enforcing" "$_m26_e39_rocky" "test \"\$(getenforce)\" = Enforcing"
  check_ssh "$_m26_e39_rocky : node_exporter actif" "$_m26_e39_rocky" \
    "u=\$(systemctl list-units --all --type=service --no-legend --plain | awk '/node_exporter/{print \$1; exit}'); systemctl is-active \"\$u\" | grep -q '^active'"
  check_ssh "$_m26_e39_rocky : aucun refus AVC récent sur node_exporter" "$_m26_e39_rocky" \
    "! sudo -n ausearch -m AVC -ts recent 2>/dev/null | grep -q node_exporter"
else
  skip "$_m26_e39_rocky" "SSH + sudo -n impossible (hôte Rocky)"
fi
check_cmd "panne M26-E39 close" _m26x_aucune_panne_active E39
