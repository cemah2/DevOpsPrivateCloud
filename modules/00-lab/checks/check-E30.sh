# shellcheck shell=bash
# Vérification M00-E30 — Sauvegarder la configuration de l'hyperviseur (lancé depuis adm01).

title "M00-E30 — Sauvegarder la configuration de l'hyperviseur"
require_cmd ssh

SCRIPT=/usr/local/sbin/wb-backup-config.sh
NODE="$(remote "$WB_PVE_HOST" hostname 2>/dev/null)" || NODE=""
[[ -n "$NODE" ]] || NODE=pve01

# Répertoire du groupe host/<nœud> dans le namespace par1 du datastore ds-lab (sur pbs01)
GROUPE_CMD="p=\$(proxmox-backup-manager datastore show ds-lab --output-format json | grep -oE '\"path\" *: *\"[^\"]+\"' | sed -E 's/.*\"([^\"]+)\"\$/\\1/'); echo \"\$p/ns/par1/host/$NODE\""
DERNIER_CMD="g=\$($GROUPE_CMD); ls -1d \"\$g\"/*/ 2>/dev/null | sort | tail -n 1"

# --- pve01 : script et timer -------------------------------------------------
check_ssh "le script $SCRIPT existe et est exécutable" "$WB_PVE_HOST" "test -x $SCRIPT"
check_ssh "le script ne contient pas le secret du jeton PBS en clair" "$WB_PVE_HOST" \
  "test -s /etc/pve/priv/storage/pbs-par2.pw && ! grep -qF -- \"\$(head -n 1 /etc/pve/priv/storage/pbs-par2.pw)\" $SCRIPT"
check_ssh "le script prend en compte la base de pmxcfs (config.db)" "$WB_PVE_HOST" "grep -q 'config\.db' $SCRIPT"
check_ssh "le timer wb-backup-config.timer est activé" "$WB_PVE_HOST" "systemctl is-enabled --quiet wb-backup-config.timer"
check_ssh "le timer wb-backup-config.timer est actif" "$WB_PVE_HOST" "systemctl is-active --quiet wb-backup-config.timer"
check_ssh_output "le timer a une prochaine échéance" "$WB_PVE_HOST" 'wb-backup-config\.timer' \
  "systemctl list-timers --no-pager wb-backup-config.timer"
check_ssh_output "le dernier passage du service s'est terminé sans erreur" "$WB_PVE_HOST" '^Result=success$' \
  "systemctl show -p Result wb-backup-config.service"
check_ssh "le service a déjà été exécuté au moins une fois" "$WB_PVE_HOST" \
  "systemctl show -p ExecMainExitTimestampMonotonic wb-backup-config.service | grep -qv '=0\$'"

# --- pbs01 : instantané host/<nœud> --------------------------------------------
check_ssh "le groupe host/$NODE existe dans le namespace par1 de ds-lab" "$WB_PBS_HOST" \
  "test -d \"\$($GROUPE_CMD)\""
check_ssh "un instantané host/$NODE de moins de 48 h existe" "$WB_PBS_HOST" \
  "find \"\$($GROUPE_CMD)\" -mindepth 1 -maxdepth 1 -type d -mmin -2880 | grep -q ."
check_ssh "le dernier instantané host/$NODE contient au moins deux archives pxar" "$WB_PBS_HOST" \
  "d=\$($DERNIER_CMD); [ -n \"\$d\" ] && [ \$(ls -1 \"\$d\" | grep -c '\.pxar\.didx\$') -ge 2 ]"
