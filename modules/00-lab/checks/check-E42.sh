# shellcheck shell=bash
# check-E42.sh — M00-E42 « Panne : la sauvegarde nocturne a échoué » : retour à l'état sain.
title "M00-E42 — Panne : la sauvegarde nocturne a échoué"

check_ssh_output "pve01 : stockage pbs-par2 actif" "$WB_PVE_HOST" '^pbs-par2[[:space:]]+pbs[[:space:]]+active' \
  "pvesm status --storage pbs-par2"
check_ssh "pve01 : contenu de pbs-par2 lisible" "$WB_PVE_HOST" "pvesm list pbs-par2 >/dev/null"
check_ssh_output "pve01 : pbs-par2 utilise le namespace par1" "$WB_PVE_HOST" '^[[:space:]]+namespace par1$' \
  "sed -n '/^pbs: pbs-par2\$/,/^[a-z]*: /p' /etc/pve/storage.cfg"
check_ssh "pbs01 : datastore ds-lab ouvert en lecture et en écriture" "$WB_PBS_HOST" \
  "! proxmox-backup-manager datastore show ds-lab --output-format json | grep -q maintenance"
check_ssh_output "pbs01 : droits de sauvegarde présents pour wb-backup@pbs" "$WB_PBS_HOST" 'wb-backup@pbs' \
  "proxmox-backup-manager acl list"
check_ssh_output "pve01 : la dernière tâche de sauvegarde s'est terminée sans erreur" "$WB_PVE_HOST" '"status" *: *"OK"' \
  "pvesh get /nodes/\$(hostname)/tasks --typefilter vzdump --limit 1 --output-format json"
