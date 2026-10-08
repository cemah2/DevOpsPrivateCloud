# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E08.sh — M08-E08 : ZFS : le stockage local en rappel
# À lancer depuis adm01. Lecture seule : qm config sur pve01, état ZFS de cephcli01 en SSH
# (zpool/zfs en lecture), API GitLab en GET.

# shellcheck source=_m08-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-decouverte.sh"

title "M08-E08 — ZFS : le stockage local en rappel"
require_cmd jq curl

_m08d_e08_cli="$_M08D_CLIENT"

# --- 1. Les disques, ajoutés par le code ----------------------------------------------------------------
_m08d_e08_conf="$(_m08d_qm 2085)"
check_cmd "cephcli01 : scsi1 et scsi2 de 8 Gio sur $_M08D_SSD (ajoutés par OpenTofu)" \
  bash -c 'for d in scsi1 scsi2; do grep -Eq "^$d: $2:.*size=8G" <<<"$1" || exit 1; done' _ "$_m08d_e08_conf" "$_M08D_SSD"
check_cmd "plateforme/infra (main) : disques ZFS déclarés dans envs/ceph/cephcli01.tf" \
  bash -c 'grep -q "cephcli01-zfs2" <<<"$1"' _ "$(_m08d_contenu_main plateforme/infra envs/ceph/cephcli01.tf)"

# --- 2. Le pool --------------------------------------------------------------------------------------------
check_ssh "cephcli01 : outils et module ZFS chargés" "$_m08d_e08_cli" 'command -v zpool >/dev/null && [ -d /sys/module/zfs ]'
check_ssh_output "cephcli01 : pool zlocal en ligne" "$_m08d_e08_cli" '^ONLINE$' 'sudo -n zpool list -H -o health zlocal'
check_ssh "cephcli01 : zlocal est un miroir de deux disques désignés par leur identifiant stable (by-id)" "$_m08d_e08_cli" \
  's=$(sudo -n zpool status -P zlocal) && grep -q "mirror-0" <<<"$s" && [ "$(grep -c "/dev/disk/by-id/.*cephcli01-zfs[12]" <<<"$s")" -eq 2 ]'
check_ssh "cephcli01 : zlocal n'est pas construit sur un périphérique Ceph (rbd)" "$_m08d_e08_cli" \
  '! sudo -n zpool status -P zlocal | grep -q "/dev/rbd"'
check_ssh "cephcli01 : un nettoyage (scrub) terminé sans erreur" "$_m08d_e08_cli" \
  'sudo -n zpool status zlocal | grep -Eq "scrub repaired .* with 0 errors"'
check_ssh "cephcli01 : aucune erreur de lecture, d'écriture ni de somme de contrôle" "$_m08d_e08_cli" \
  'sudo -n zpool status -x zlocal | grep -q "is healthy"'
check_ssh "cephcli01 : le pool est réimporté au démarrage (zfs-import-cache, zfs-mount actifs)" "$_m08d_e08_cli" \
  'systemctl is-enabled --quiet zfs-import-cache.service && systemctl is-enabled --quiet zfs-mount.service'

# --- 3. Datasets, instantanés, réplication -------------------------------------------------------------------
check_ssh "cephcli01 : dataset zlocal/donnees compressé (compression active)" "$_m08d_e08_cli" \
  'c=$(sudo -n zfs get -H -o value compression zlocal/donnees) && [ -n "$c" ] && [ "$c" != off ]'
check_ssh "cephcli01 : au moins deux instantanés de zlocal/donnees" "$_m08d_e08_cli" \
  '[ "$(sudo -n zfs list -H -t snapshot -o name -r zlocal/donnees | grep -c "^zlocal/donnees@")" -ge 2 ]'
check_ssh "cephcli01 : zlocal/copie reçu par zfs send/receive (instantanés communs, même identifiant)" "$_m08d_e08_cli" \
  'src=$(sudo -n zfs get -H -o value guid -t snapshot -r zlocal/donnees | sort); dst=$(sudo -n zfs get -H -o value guid -t snapshot -r zlocal/copie | sort); [ -n "$dst" ] && [ "$(comm -12 <(echo "$src") <(echo "$dst") | wc -l)" -ge 2 ]'
