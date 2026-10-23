# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes exécutées DANS les VMs (expansion côté invité, voulue)
# check-S11.sh — F4-S11 « Panne : la VM migrée ne démarre pas comme avant » (INC-6011). Lecture seule.
# Contrôle ftp-part01 ET stats01 (la variante injectée n'est pas révélée) : démarrées APRÈS l'injection
# (marqueur de lab/bin/break), agent, adresse, service, configuration Proxmox conforme, causes levées.

# shellcheck source=_f4-migrations.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f4-migrations.sh"

title "F4-S11 — La VM migrée ne démarre pas comme avant"
require_cmd jq ssh

_f4_s11_marqueur="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives/F4-S11"

# _f4_s11_redemarree VMID — la VM tourne depuis moins longtemps que la panne n'existe.
_f4_s11_redemarree() {
  local uptime age
  uptime="$(_f4g_pve "qm status $1 --verbose" 2>/dev/null | sed -nE 's/^uptime: ([0-9]+)$/\1/p')"
  [[ "$uptime" =~ ^[0-9]+$ ]] || return 1
  age=$(($(date +%s) - $(stat -c %Y "$_f4_s11_marqueur")))
  ((uptime < age))
}

for _f4_s11_nom in ftp-part01 stats01; do
  _f4_s11_id="$(_f4g_vmid "$_f4_s11_nom")"
  _f4_s11_ip="$(_f4g_ip "$_f4_s11_nom")"
  check_cmd "$_f4_s11_nom : démarrée" _f4g_vm_filtre "$_f4_s11_id" '.status == "running"'
  if [[ -f "$_f4_s11_marqueur" ]]; then
    # Variante 2 sur ftp-part01, 1 et 3 sur stats01 : seule la VM visée doit avoir redémarré.
    _f4_s11_var="$(cat "$_f4_s11_marqueur" 2>/dev/null || true)"
    if { [[ "$_f4_s11_var" == 2 ]] && [[ "$_f4_s11_nom" == ftp-part01 ]]; } || \
       { [[ "$_f4_s11_var" =~ ^[13]$ ]] && [[ "$_f4_s11_nom" == stats01 ]]; }; then
      check_cmd "$_f4_s11_nom : a redémarré après l'incident (réparation constatée au démarrage)" _f4_s11_redemarree "$_f4_s11_id"
    fi
  fi
  check_cmd "$_f4_s11_nom : configuration Proxmox conforme (VirtIO SCSI, scsi0, carte virtio sur vinfra, agent)" _f4g_conforme "$_f4_s11_id"
  if _f4g_agent "$_f4_s11_id"; then
    check_cmd "$_f4_s11_nom : l'agent QEMU répond" true
    check_output "$_f4_s11_nom : l'invité porte $_f4_s11_ip" "^${_f4_s11_ip//./\\.}$" _f4g_ips "$_f4_s11_id"
    check_cmd "$_f4_s11_nom : fstab sans nom de périphérique /dev/sdX ni /dev/vdX" _f4g_invite "$_f4_s11_id" \
      '! grep -Eq "^[[:space:]]*/dev/(sd|vd)[a-z]" /etc/fstab'
    check_cmd "$_f4_s11_nom : l'initramfs du noyau courant contient virtio_scsi" _f4g_invite "$_f4_s11_id" \
      'lsinitramfs "/boot/initrd.img-$(uname -r)" | grep -q virtio_scsi'
    check_cmd "$_f4_s11_nom : aucun nom d'interface figé sur une MAC absente" _f4g_invite "$_f4_s11_id" \
      'for l in /etc/systemd/network/*.link; do [ -e "$l" ] || continue; m=$(sed -n "s/^MACAddress=//p" "$l"); [ -z "$m" ] || grep -qix "$m" /sys/class/net/*/address || exit 1; done; exit 0'
  else
    check_cmd "$_f4_s11_nom : l'agent QEMU répond" false
  fi
done
check_port "ftp-part01 accepte les connexions FTP (21)" 10.10.20.45 21
if _f4g_agent 3403; then
  check_cmd "stats01 : la base de Legacy-RDV est joignable avec le compte stats (lecture)" _f4g_invite 3403 \
    'mariadb --defaults-extra-file=/etc/stats/stats.cnf -N -B --connect-timeout=5 -e "SELECT 1" >/dev/null 2>&1 || ! test -f /etc/cron.d/stats-rdv'
fi
check_cmd "post-mortem INC-6011 sur main ($_f4g_doc_dir/post-mortems/) : cause et prévention" \
  _f4g_doc "$_f4g_doc_dir/post-mortems" '^INC-6011' 'cause' 'pr(é|e)vention|ne se reproduise'
