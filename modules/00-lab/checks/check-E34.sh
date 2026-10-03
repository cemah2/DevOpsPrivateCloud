# shellcheck shell=bash
# Vérification M00-E34 — Mises à jour maîtrisées de pve01 et pbs01 (lancé depuis adm01).

title "M00-E34 — Mises à jour maîtrisées de pve01 et pbs01"
require_cmd ssh

# Commandes distantes communes à pve01 et pbs01
LISTES_RECENTES="find /var/lib/apt/lists -maxdepth 1 -name '*Packages*' -mtime -7 | grep -q ."
AUCUNE_MAJ="LC_ALL=C apt-get -s -o Debug::NoLocking=1 dist-upgrade | grep -Eq '^0 upgraded, 0 newly installed'"
NOYAU_OK="r=\$(uname -r); if proxmox-boot-tool kernel list 2>/dev/null | grep -qi '^pinned'; then proxmox-boot-tool kernel list | grep -iA1 '^pinned' | grep -qx \"\$r\"; else [ \"\$r\" = \"\$(ls -1 /lib/modules | grep -- '-pve\$' | sort -V | tail -n 1)\" ]; fi"
AUCUN_ECHEC="! systemctl --failed --no-legend --plain | grep -q ."

for hote in "$WB_PVE_HOST" "$WB_PBS_HOST"; do
  check_ssh "$hote : listes de paquets mises à jour il y a moins de 7 jours" "$hote" "$LISTES_RECENTES"
  check_ssh "$hote : aucune mise à jour en attente" "$hote" "$AUCUNE_MAJ"
  check_ssh "$hote : le noyau en service est le plus récent installé (ou celui épinglé)" "$hote" "$NOYAU_OK"
  check_ssh "$hote : aucun service systemd en échec" "$hote" "$AUCUN_ECHEC"
done

check_ssh_output "pve01 : pve-manager installé et lisible" "$WB_PVE_HOST" '^pve-manager/' "pveversion"
check_ssh_output "pbs01 : proxmox-backup-server installé et lisible" "$WB_PBS_HOST" 'proxmox-backup-server' \
  "proxmox-backup-manager versions"

for vmid in 1000 1001 1002; do
  check_ssh_output "VM $vmid en marche" "$WB_PVE_HOST" '^status: running$' "qm status $vmid"
  check_ssh "VM $vmid : aucun snapshot avant-maj-* restant" "$WB_PVE_HOST" "! qm listsnapshot $vmid | grep -q 'avant-maj-'"
done

check_ssh "pbs01 : le datastore ds-lab n'est pas en mode maintenance" "$WB_PBS_HOST" \
  "proxmox-backup-manager datastore show ds-lab --output-format json >/dev/null && ! proxmox-backup-manager datastore show ds-lab --output-format json | grep -q 'maintenance-mode'"
check_ssh_output "pve01 : le stockage pbs-par2 est actif" "$WB_PVE_HOST" '^pbs-par2 +pbs +active' "pvesm status"
