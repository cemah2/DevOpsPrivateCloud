# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées sur l'hôte distant
#
# check-E08.sh — M09-E08 : Un troisième nœud
# À lancer depuis adm01. Lecture seule : VM 2093 sur pve01, hv03 en root, pvecm et Corosync,
# stockage zfs-local, services QDevice, état de corosync-qnetd et pare-feu de pbs01.

# shellcheck source=_m09-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-decouverte.sh"

title "M09-E08 — Un troisième nœud"
require_cmd jq dig

# --- hv03, par le même chemin que les deux premiers ----------------------------------------------------
check_cmd "plateforme/ansible (copie de travail) : hv03 dans l'inventaire hv.yml" \
  grep -Eq '^[[:space:]]+hv03:' "$_M09D_ANSIBLE/inventories/lab/hv.yml"
_m09d_controler_vm_noeud hv03 3
_m09d_controler_noeud_configure hv03 3

# --- Le cluster à trois -------------------------------------------------------------------------------
_m09d_e08_statut="$(_m09d_hv hv01 'pvecm status')"
check_cmd "Trois nœuds membres, quorum atteint" \
  bash -c 'grep -Eq "^Nodes:[[:space:]]+3$" <<<"$1" && grep -Eq "^Quorate:[[:space:]]+Yes$" <<<"$1"' _ "$_m09d_e08_statut"
check_cmd "3 votes attendus, 3 votes présents, quorum à 2" \
  bash -c 'grep -Eq "^Expected votes:[[:space:]]+3$" <<<"$1" && grep -Eq "^Total votes:[[:space:]]+3$" <<<"$1" && grep -Eq "^Quorum:[[:space:]]+2( |$)" <<<"$1"' _ "$_m09d_e08_statut"
check_cmd "Plus de QDevice dans le cluster (nombre impair de nœuds)" \
  bash -c 'grep -q "^Name:" <<<"$1" && ! grep -q "Qdevice" <<<"$1"' _ "$_m09d_e08_statut"
check_cmd "hv03 : lien 0 = 10.10.32.53, lien 1 = 10.10.10.53" _m09d_anneaux hv01 hv03 10.10.32.53 10.10.10.53
check_ssh "hv03 : deux liens knet, aucun pair déconnecté" hv03 \
  'o=$(corosync-cfgtool -s) && [ "$(grep -c "^LINK ID" <<<"$o")" -ge 2 ] && ! grep -qi "disconnected" <<<"$o"'
for _m09d_e08_n in hv01 hv02 hv03; do
  check_ssh "$_m09d_e08_n : corosync-qdevice arrêté et désactivé" "$_m09d_e08_n" \
    '! systemctl is-active --quiet corosync-qdevice && ! systemctl is-enabled --quiet corosync-qdevice 2>/dev/null'
done

# --- Stockage local de hv03 -------------------------------------------------------------------------------
check_ssh "hv03 : pool tank en ligne sur le disque de série hv03-zfs" hv03 \
  'zpool list -H -o health tank | grep -qx ONLINE && lsblk -nro FSTYPE /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_hv03-zfs | grep -q zfs_member'
check_ssh "zfs-local déclaré pour hv03 et actif sur hv03" hv03 \
  'pvesh get /storage/zfs-local --output-format json | jq -e ".nodes | split(\",\") | index(\"hv03\") != null" >/dev/null && pvesm status --storage zfs-local | awk "NR>1 {print \$3}" | grep -qx active'

# --- pbs01 rendu à son seul métier -------------------------------------------------------------------------
check_ssh "pbs01 : corosync-qnetd arrêté et désactivé" "$_M09D_PBS" \
  '! systemctl is-active --quiet corosync-qnetd && ! systemctl is-enabled --quiet corosync-qnetd 2>/dev/null'
check_ssh "pbs01 : plus de port 5403 ouvert" "$_M09D_PBS" '! nft list ruleset | grep -q "dport 5403"'
check_cmd "Matrice des flux (pare_feu.yml de gw01) : règle du QDevice retirée" \
  bash -c 'f="$1/inventories/lab/host_vars/gw01/pare_feu.yml"; [ -s "$f" ] && ! grep -Eq "ports: *5403" "$f"' _ "$_M09D_ANSIBLE"
check_ssh "gw01 : plus de règle TCP 5403 chargée" gw01 '! sudo -n nft list ruleset | grep -q "dport 5403"'
