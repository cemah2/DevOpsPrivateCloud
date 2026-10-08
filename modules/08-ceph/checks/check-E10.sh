# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
#
# check-E10.sh — M08-E10 : CephFS : volumes, sous-volumes et clients
# À lancer depuis adm01. Lecture seule (ceph fs dump/info, auth get, findmnt, stat).

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E10 — CephFS : volumes, sous-volumes et clients"
require_cmd jq ssh

_m08o_dump="$(_m08o_ceph fs dump --format json)"
_m08o_hotes="$(_m08o_ceph orch host ls --format json)"
_m08o_mds="$(_m08o_ceph orch ps --daemon_type mds --format json)"
_m08o_sv="$(_m08o_ceph fs subvolume info cephfs outillage --group_name plateforme)"
_m08o_groupes="$(_m08o_ceph fs subvolumegroup ls cephfs)"
_m08o_auth="$(_m08o_ceph auth get client.outillage --format json)"
_m08o_snaps="$(_m08o_ceph fs subvolume snapshot ls cephfs outillage --group_name plateforme)"

# --- Le volume et ses MDS -----------------------------------------------------------------------
check_cmd "le système de fichiers cephfs existe" \
  jq -e '[.filesystems[] | select(.mdsmap.fs_name == "cephfs")] | length == 1' <<<"$_m08o_dump"
check_cmd "cephfs a un MDS actif" \
  jq -e '[.filesystems[] | select(.mdsmap.fs_name == "cephfs") | .mdsmap.info[] | select(.state == "up:active")] | length >= 1' <<<"$_m08o_dump"
check_cmd "au moins un MDS en attente (bascule possible)" \
  jq -e '((.standbys // []) | length) + ([.filesystems[] | select(.mdsmap.fs_name == "cephfs") | .mdsmap.info[] | select(.state == "up:standby-replay")] | length) >= 1' <<<"$_m08o_dump"
_m08o_mds_etiquetes() {
  jq -e -n --argjson h "$_m08o_hotes" --argjson d "$_m08o_mds" '
    ($h | map(select((.labels // []) | index("mds")) | .hostname)) as $avec
    | ($d | length) >= 2 and ($d | all(.hostname as $x | $avec | index($x)))' >/dev/null 2>&1
}
check_cmd "les démons MDS (au moins deux) tournent sur des hôtes étiquetés « mds »" _m08o_mds_etiquetes
_m08o_cache="$(_m08o_ceph config get mds mds_cache_memory_limit | tr -d '[:space:]')"
check_output "cache des MDS plafonné (≤ 1 Gio ; valeur : ${_m08o_cache:-?})" '^(1073741824|[1-9][0-9]{0,8})$' echo "$_m08o_cache"

# --- Sous-volumes ----------------------------------------------------------------------------------
check_cmd "sous-volume plateforme/outillage avec un quota de 10 Gio" \
  jq -e '.bytes_quota == 10737418240' <<<"$_m08o_sv"
check_cmd "le groupe de sous-volumes « applications » existe" \
  jq -e 'map(.name) | index("applications") != null' <<<"$_m08o_groupes"
check_cmd "au moins un instantané du sous-volume outillage" jq -e 'length >= 1' <<<"$_m08o_snaps"

# --- Le client -----------------------------------------------------------------------------------
_m08o_chemin="$(jq -r '.path // ""' <<<"$_m08o_sv" 2>/dev/null || true)"
check_cmd "client.outillage : droits MDS limités au chemin du sous-volume" \
  jq -e --arg p "${_m08o_chemin:-/volumes/plateforme/outillage}" '
    .[0].caps.mds as $m | ($m | test("path=")) and ([$m | scan("path=([^ ,]+)")[]] | all(startswith($p)))' <<<"$_m08o_auth"
check_cmd "client.outillage : aucun droit d'administration (pas de « allow * » ni d'écriture moniteur)" \
  jq -e '.[0].caps | ((.mon // "") | test("allow (\\*|rw)") | not) and ((.mds // "") | test("allow \\*") | not)' <<<"$_m08o_auth"
check_cmd "cephcli01 : /etc/ceph/outillage.secret en 600, propriétaire root" \
  _m08o_root600 "$_M08O_CLIENT" /etc/ceph/outillage.secret
check_ssh "cephcli01 : /mnt/outillage monté en ceph" "$_M08O_CLIENT" \
  'findmnt -n -t ceph /mnt/outillage >/dev/null'
check_ssh "cephcli01 : montage permanent dans /etc/fstab (ceph, _netdev)" "$_M08O_CLIENT" \
  'grep -Ev "^[[:space:]]*#" /etc/fstab | grep -E "[[:space:]]/mnt/outillage[[:space:]]+ceph[[:space:]]" | grep -q _netdev'
check_ssh "cephcli01 : aucune clé écrite en clair dans /etc/fstab (secret=)" "$_M08O_CLIENT" \
  '! grep -Ev "^[[:space:]]*#" /etc/fstab | grep -qE "(^|[ ,])secret="'
