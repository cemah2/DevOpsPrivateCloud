# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E22.sh — M00-E22 : Datastore, rétention et tâches de sauvegarde
# À lancer depuis adm01, après au moins une exécution de la tâche de sauvegarde. Lecture seule.

title "M00-E22 — Datastore, rétention et tâches de sauvegarde"

# --- PBS ---
check_ssh "pbs01 : datastore ds-lab déclaré" "$WB_PBS_HOST" \
  'proxmox-backup-manager datastore list --output-format json | grep -Eq "\"name\" *: *\"ds-lab\""'
check_ssh "pbs01 : ds-lab n'est pas sur le système de fichiers racine" "$WB_PBS_HOST" \
  'p=$(proxmox-backup-manager datastore show ds-lab --output-format json | sed -nE "s/.*\"path\" *: *\"([^\"]+)\".*/\1/p"); test -n "$p" && test "$(findmnt -n -o TARGET --target "$p")" != "/"'
check_ssh "pbs01 : namespace par1 présent dans ds-lab" "$WB_PBS_HOST" \
  'p=$(proxmox-backup-manager datastore show ds-lab --output-format json | sed -nE "s/.*\"path\" *: *\"([^\"]+)\".*/\1/p"); test -n "$p" && test -d "$p/ns/par1"'
check_ssh "pbs01 : jeton wb-backup@pbs!pve01 existant" "$WB_PBS_HOST" \
  'proxmox-backup-manager user list-tokens wb-backup@pbs --output-format json | grep -qF "wb-backup@pbs!pve01"'
check_ssh "pbs01 : le jeton peut sauvegarder dans ds-lab/par1" "$WB_PBS_HOST" \
  'proxmox-backup-manager user permissions "wb-backup@pbs!pve01" --path /datastore/ds-lab/par1 | grep -q "Datastore\.Backup"'
check_ssh "pbs01 : le jeton ne peut ni purger ni modifier le datastore" "$WB_PBS_HOST" \
  '! proxmox-backup-manager user permissions "wb-backup@pbs!pve01" --path /datastore/ds-lab/par1 | grep -Eq "Datastore\.(Prune|Modify)"'
check_ssh "pbs01 : une tâche de purge (prune) est planifiée sur ds-lab" "$WB_PBS_HOST" \
  'proxmox-backup-manager prune-job list --output-format json | grep -q "\"ds-lab\""'
check_ssh "pbs01 : rétention 7 quotidiennes / 4 hebdomadaires / 6 mensuelles" "$WB_PBS_HOST" \
  'j=$(proxmox-backup-manager prune-job list --output-format json); echo "$j" | grep -Eq "\"keep-daily\" *: *7" && echo "$j" | grep -Eq "\"keep-weekly\" *: *4" && echo "$j" | grep -Eq "\"keep-monthly\" *: *6"'
check_ssh "pbs01 : ramasse-miettes (GC) planifié sur ds-lab" "$WB_PBS_HOST" \
  'proxmox-backup-manager datastore show ds-lab --output-format json | grep -q "\"gc-schedule\""'
check_ssh "pbs01 : vérification planifiée sur ds-lab" "$WB_PBS_HOST" \
  'j=$(proxmox-backup-manager verify-job list --output-format json); echo "$j" | grep -q "\"ds-lab\"" && echo "$j" | grep -q "\"schedule\""'

# --- PVE ---
check_ssh "pve01 : stockage pbs-par2 actif" "$WB_PVE_HOST" \
  'pvesm status --storage pbs-par2 2>/dev/null | grep -Eq "^pbs-par2[[:space:]]+pbs[[:space:]]+active"'
check_ssh_output "pve01 : pbs-par2 → 10.20.10.10, datastore ds-lab, namespace par1" "$WB_PVE_HOST" '^3$' \
  'awk "/^pbs: pbs-par2\$/ {s=1; next} /^[a-z]+: / {s=0} s" /etc/pve/storage.cfg | grep -cE "^[[:space:]]+(server 10\.20\.10\.10|datastore ds-lab|namespace par1)[[:space:]]*$"'
check_ssh "pve01 : pbs-par2 épingle l'empreinte du certificat et utilise le jeton" "$WB_PVE_HOST" \
  's=$(awk "/^pbs: pbs-par2\$/ {s=1; next} /^[a-z]+: / {s=0} s" /etc/pve/storage.cfg); echo "$s" | grep -q "fingerprint " && echo "$s" | grep -qF "username wb-backup@pbs!pve01"'
check_ssh "pve01 : tâche planifiée du pool lab vers pbs-par2 (mode snapshot)" "$WB_PVE_HOST" \
  'pvesh get /cluster/backup --output-format json | tr "}" "\n" | grep -E "\"pool\" *: *\"lab\"" | grep -E "\"storage\" *: *\"pbs-par2\"" | grep -E "\"schedule\"" | grep -Evq "\"mode\" *: *\"(stop|suspend)\""'
check_ssh "pve01 : chaque VM du socle (1000-1099) du pool lab a une sauvegarde dans pbs-par2" "$WB_PVE_HOST" \
  'ids=$(pvesh get /cluster/resources --type vm --output-format json | tr "}" "\n" | grep -E "\"pool\" *: *\"lab\"" | sed -nE "s/.*\"vmid\" *: *(10[0-9]{2})([^0-9].*|$)/\1/p"); test -n "$ids" || exit 1; l=$(pvesm list pbs-par2 --content backup); for i in $ids; do echo "$l" | grep -q "backup/vm/$i/" || exit 1; done'
