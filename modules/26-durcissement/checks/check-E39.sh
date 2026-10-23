# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E39.sh — M26-E39 « service confiné » : Mailpit (mon01) tourne avec son profil AppArmor en enforce
# et sans drop-in qui vide ses exceptions ; sur l'hôte Rocky, SELinux enforcing et la vérification AIDE
# (aide_t) n'est pas en échec, sans refus AVC récent ; panne close. Lecture seule.
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
  # /sys/kernel/security/apparmor/profiles : « <nom> (enforce|complain) » ; un profil en complain ne passe pas.
  check_ssh "$_m26_e39_mon : profil AppArmor de Mailpit chargé en enforce" "$_m26_e39_mon" \
    "sudo -n cat /sys/kernel/security/apparmor/profiles 2>/dev/null | grep -Eq '^(/opt/mailpit/[^ ]*/mailpit|mailpit) \\(enforce\\)\$'"
  check_ssh "$_m26_e39_mon : aucun drop-in ne vide ReadWritePaths de Mailpit" "$_m26_e39_mon" \
    "! systemctl cat mailpit 2>/dev/null | grep -Eq '^ReadWritePaths=[[:space:]]*\$'"
else
  skip "$_m26_e39_mon" "SSH + sudo -n impossible"
fi
if _m26x_ssh_ok "$_m26_e39_rocky"; then
  check_ssh "$_m26_e39_rocky : SELinux toujours en enforcing" "$_m26_e39_rocky" "test \"\$(getenforce)\" = Enforcing"
  check_ssh "$_m26_e39_rocky : la vérification AIDE (aide_t) n'est pas en échec" "$_m26_e39_rocky" \
    "! systemctl is-failed --quiet aide-verification.service"
  check_ssh "$_m26_e39_rocky : /var/log/aide a le contexte de la politique" "$_m26_e39_rocky" \
    "test \"\$(stat -c %C /var/log/aide | cut -d: -f3)\" = \"\$(matchpathcon -n /var/log/aide | cut -d: -f3)\""
  check_ssh "$_m26_e39_rocky : aucun refus AVC récent pour aide" "$_m26_e39_rocky" \
    "! sudo -n ausearch -m AVC -ts recent 2>/dev/null | grep -q 'comm=\"aide\"'"
else
  skip "$_m26_e39_rocky" "SSH + sudo -n impossible (hôte Rocky)"
fi
check_cmd "panne M26-E39 close" _m26x_aucune_panne_active E39
