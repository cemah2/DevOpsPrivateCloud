# shellcheck shell=bash
# Vérification M00-E32 — Optimiser la configuration des VMs du socle (lancé depuis adm01).

title "M00-E32 — Optimiser la configuration des VMs du socle"
require_cmd ssh

# vmid:nom:ordre
for vm in 1000:gw01:1 1002:dns01:2 1001:adm01:3; do
  IFS=: read -r vmid nom ordre <<<"$vm"
  conf="qm config $vmid --current"

  check_ssh_output "$nom : démarrage automatique" "$WB_PVE_HOST" '^onboot: 1$' "$conf"
  check_ssh_output "$nom : ordre de démarrage $ordre" "$WB_PVE_HOST" "^startup: (.*,)?order=$ordre(,|\$)" "$conf"
  check_ssh_output "$nom : agent QEMU activé dans la configuration" "$WB_PVE_HOST" '^agent: (1|enabled=1)(,|$)' "$conf"
  check_ssh "$nom : l'agent QEMU répond" "$WB_PVE_HOST" "qm agent $vmid ping"
  check_ssh_output "$nom : contrôleur virtio-scsi-single" "$WB_PVE_HOST" '^scsihw: virtio-scsi-single$' "$conf"
  check_ssh "$nom : tous les disques ont discard=on" "$WB_PVE_HOST" \
    "$conf | grep -E '^(scsi|virtio|sata)[0-9]+: ' | grep -v 'media=cdrom' | grep -q . && ! $conf | grep -E '^(scsi|virtio|sata)[0-9]+: ' | grep -v 'media=cdrom' | grep -v 'cloudinit' | grep -vq 'discard=on'"
  check_ssh "$nom : iothread activé sur les disques SCSI" "$WB_PVE_HOST" \
    "! $conf | grep -E '^scsi[0-9]+: ' | grep -v 'media=cdrom' | grep -v 'cloudinit' | grep -vq 'iothread=1'"
  check_ssh_output "$nom : type de CPU explicite" "$WB_PVE_HOST" '^cpu: ' "$conf"
  check_ssh "$nom : type de CPU ni kvm64 ni qemu64 ni host" "$WB_PVE_HOST" \
    "$conf | grep '^cpu: ' | grep -qvE '(^cpu: |cputype=)(kvm64|qemu64|host)(,|\$)'"
  check_ssh "$nom : aucune modification en attente" "$WB_PVE_HOST" \
    "! qm pending $vmid | grep -Eq '^(new|del)'"
done
