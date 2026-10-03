# shellcheck shell=bash
# Vérification M00-E29 — Notifications Proxmox et PBS (lancé depuis adm01).

title "M00-E29 — Notifications Proxmox et PBS"
require_cmd ssh

# --- pve01 ----------------------------------------------------------------------
check_ssh "pve01 : une cible de notification autre que mail-to-root existe" "$WB_PVE_HOST" \
  "pvesh get /cluster/notifications/targets --output-format json | grep -oE '\"name\" *: *\"[^\"]+\"' | grep -qv 'mail-to-root'"
check_ssh_output "pve01 : un filtre sélectionne les notifications de sauvegarde (type vzdump)" "$WB_PVE_HOST" \
  'type=vzdump' "pvesh get /cluster/notifications/matchers --output-format json"
check_ssh "pve01 : aucune tâche de sauvegarde n'utilise l'ancien envoi de mail direct" "$WB_PVE_HOST" \
  "! grep -Eq '^[[:space:]]+notification-mode[[:space:]]+legacy-sendmail' /etc/pve/jobs.cfg"
check_ssh_output "pve01 : au moins une tâche de sauvegarde planifiée existe" "$WB_PVE_HOST" \
  '^vzdump: ' "cat /etc/pve/jobs.cfg"

# --- pbs01 ----------------------------------------------------------------------
check_ssh "pbs01 : une cible de notification autre que mail-to-root existe" "$WB_PBS_HOST" \
  "proxmox-backup-manager notification target list --output-format json | grep -oE '\"name\" *: *\"[^\"]+\"' | grep -qv 'mail-to-root'"
check_ssh "pbs01 : un filtre autre que le filtre par défaut existe" "$WB_PBS_HOST" \
  "proxmox-backup-manager notification matcher list --output-format json | grep -oE '\"name\" *: *\"[^\"]+\"' | grep -qv 'default-matcher'"
check_ssh "pbs01 : le datastore ds-lab n'utilise pas l'ancien envoi de mail direct" "$WB_PBS_HOST" \
  "proxmox-backup-manager datastore show ds-lab --output-format json >/dev/null && ! proxmox-backup-manager datastore show ds-lab --output-format json | grep -q 'legacy-sendmail'"
