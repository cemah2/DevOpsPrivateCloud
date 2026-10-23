# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
# check-E22.sh — M29-E22 « Panne : les tests d'infrastructure sont rouges » : sur chaque VM de
# WB_M29_E22_HOTES, chrony synchronisé sur une source du lab, sshd effectif conforme (aucun fichier de
# sshd_config.d qui ne vienne ni d'Ansible ni de l'image dorée — 50-cloud-init.conf toléré —, X11 interdit), node_exporter actif et activé ; panne close.
# Lecture seule (SSH + sudo -n de commandes de consultation).

# shellcheck source=_m29-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-expert.sh"

title "M29-E22 — Les VMs du socle sont revenues dans l'état voulu"
require_cmd ssh

read -r -a _m29_e22_hotes <<<"${WB_M29_E22_HOTES:-nbx01 mon01}"
for _m29_e22_h in "${_m29_e22_hotes[@]}"; do
  if ! remote "$_m29_e22_h" true </dev/null >/dev/null 2>&1; then
    skip "$_m29_e22_h" "SSH impossible depuis adm01"
    continue
  fi
  check_cmd "$_m29_e22_h : chrony synchronisé (Leap status Normal), source dans 10.10.0.0/16 joignable" _m29x_hote "$_m29_e22_h" \
    'chronyc -n tracking | grep -q "^Leap status *: Normal" && chronyc -n sources | grep -E "^\^\*" | grep -q " 10\.10\."'
  check_cmd "$_m29_e22_h : chaque fichier de /etc/ssh/sshd_config.d vient d'Ansible ou de l'image dorée" _m29x_hote "$_m29_e22_h" \
    'for f in /etc/ssh/sshd_config.d/*.conf; do [ -e "$f" ] || continue; [ "${f##*/}" = 50-cloud-init.conf ] && continue; head -n 3 "$f" | grep -Eqi "ansible|image dor" || exit 1; done'
  check_cmd "$_m29_e22_h : sshd effectif sans X11Forwarding, MaxAuthTries ≤ 6" _m29x_hote "$_m29_e22_h" \
    'sshd -T | grep -qx "x11forwarding no" && [ "$(sshd -T | awk "/^maxauthtries /{print \$2}")" -le 6 ]'
  check_cmd "$_m29_e22_h : node_exporter actif et activé" _m29x_hote "$_m29_e22_h" \
    'systemctl is-active --quiet node_exporter && systemctl is-enabled --quiet node_exporter'
done
check_cmd "panne M29-E22 close (lab/bin/break 29 22 --annuler après réparation)" _m29x_aucune_panne_active E22
