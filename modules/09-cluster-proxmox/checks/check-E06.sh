# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées sur l'hôte distant
#
# check-E06.sh — M09-E06 : Stockages et réseaux des invités
# À lancer depuis adm01. Lecture seule : pvesh get, pvesm status, zpool, lsblk en root sur
# hv01 et hv02 (et hv03 s'il est déjà membre).

# shellcheck source=_m09-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-decouverte.sh"

title "M09-E06 — Stockages et réseaux des invités"
require_cmd jq

_m09d_e06_zfs="$(_m09d_hv hv01 'pvesh get /storage/zfs-local --output-format json')"
check_cmd "Stockage zfs-local : type zfspool, pool tank, images et conteneurs" \
  jq -e '.type == "zfspool" and .pool == "tank" and (.content | split(",") | index("images") != null)' <<<"$_m09d_e06_zfs"
check_cmd "zfs-local : non partagé, restreint aux nœuds qui ont le pool (hv01, hv02 au moins)" \
  jq -e '((.shared // 0) == 0) and ((.nodes // "") | split(",") | (index("hv01") != null and index("hv02") != null))' <<<"$_m09d_e06_zfs"
check_cmd "Stockage local : contenus import et snippets ajoutés" \
  bash -c '_c=$(jq -r .content <<<"$1"); grep -qw import <<<"${_c//,/ }" && grep -qw snippets <<<"${_c//,/ }"' \
  _ "$(_m09d_hv hv01 'pvesh get /storage/local --output-format json')"

for _m09d_e06_n in hv01 hv02; do
  check_ssh "$_m09d_e06_n : pool tank en ligne, sur le disque de série $_m09d_e06_n-zfs" "$_m09d_e06_n" \
    "zpool list -H -o health tank | grep -qx ONLINE && lsblk -nro FSTYPE /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_$_m09d_e06_n-zfs | grep -q zfs_member"
  check_ssh "$_m09d_e06_n : disques OSD laissés vierges (réservés à Ceph)" "$_m09d_e06_n" \
    "for d in osd1 osd2; do [ -z \"\$(lsblk -nro FSTYPE /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_$_m09d_e06_n-\$d | tr -d '[:space:]')\" ] || exit 1; done"
  check_ssh "$_m09d_e06_n : zfs-local actif" "$_m09d_e06_n" \
    'pvesm status --storage zfs-local 2>/dev/null | awk "NR>1 {print \$3}" | grep -qx active'
  check_ssh "$_m09d_e06_n : ARC de ZFS plafonné à 1 Gio au plus (en service)" "$_m09d_e06_n" \
    'v=$(cat /sys/module/zfs/parameters/zfs_arc_max); [ "$v" -gt 0 ] && [ "$v" -le 1073741824 ]'
  check_ssh "$_m09d_e06_n : fragment cloud-init medisphere-agent.yaml présent" "$_m09d_e06_n" \
    'test -s /var/lib/vz/snippets/medisphere-agent.yaml'
done

# --- Le template des invités ------------------------------------------------------------------------
_m09d_e06_tpl="$(_m09d_config_invite hv01 199)"
check_cmd "Template 199 « tpl-nested-debian13 »" jq -e '.name == "tpl-nested-debian13" and .template == 1' <<<"$_m09d_e06_tpl"
check_cmd "Template 199 : carte sur vmbr1, VLAN 99" \
  jq -e '.net0 | test("bridge=vmbr1") and test("tag=99")' <<<"$_m09d_e06_tpl"
check_cmd "Template 199 : cloud-init (lecteur, compte admin, DHCP, fragment vendor commun)" \
  jq -e '(.ide2 // "" | test("cloudinit")) and .ciuser == "admin" and (.ipconfig0 // "" | test("ip=dhcp"))
         and (.cicustom // "" | test("vendor=local:snippets/medisphere-agent.yaml"))' <<<"$_m09d_e06_tpl"
check_cmd "Template 199 : agent QEMU déclaré, CPU migrable (pas « host »)" \
  jq -e '(.agent // "" | tostring | test("^(1|enabled=1)")) and ((.cpu // "") | test("host") | not)' <<<"$_m09d_e06_tpl"
