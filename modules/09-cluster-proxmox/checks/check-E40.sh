# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur le nœud distant
# check-E40.sh — M09-E40 « Panne : la réplication est en échec » : aucun job de réplication en échec
# sur le cluster, SSH root entre nœuds par les clés du cluster, pools ZFS sains et pas trop pleins.
# Lecture seule.

# shellcheck source=_m09-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-expert.sh"

title "M09-E40 — Réplication ZFS saine"
require_cmd ssh jq

for _m09_e40_n in "${_m09x_noeuds[@]}"; do
  _m09_e40_c="$(_m09x_cible "$_m09_e40_n")"
  check_output "$_m09_e40_n : aucun job de réplication en échec" '^0$' \
    bash -c 'jq "[.[] | select((.fail_count // 0) > 0 or ((.error // \"\") != \"\"))] | length" <<<"$1" 2>/dev/null || echo erreur' _ \
    "$(_m09x_json "$_m09_e40_n" "/nodes/$_m09_e40_n/replication")"
  check_ssh "$_m09_e40_n : pools ZFS en ligne (zpool status -x)" "$_m09_e40_c" \
    'zpool status -x | grep -q "all pools are healthy"'
  check_ssh "$_m09_e40_n : pool de zfs-local rempli à moins de 80 %" "$_m09_e40_c" '
    p=$(awk "/^[a-z]+: /{d=(\$2==\"zfs-local\")} d&&\$1==\"pool\"{print \$2; exit}" /etc/pve/storage.cfg); p=${p%%/*}
    [ -n "$p" ] && [ "$(zpool list -Hp -o capacity "$p")" -lt 80 ]'
  for _m09_e40_d in "${_m09x_noeuds[@]}"; do
    [[ "$_m09_e40_n" != "$_m09_e40_d" ]] || continue
    check_ssh "$_m09_e40_n → $_m09_e40_d : SSH root par la clé du cluster" "$_m09_e40_c" \
      "ssh -o BatchMode=yes -o ConnectTimeout=5 -o HostKeyAlias=$_m09_e40_d root@${_m09x_ip[$_m09_e40_d]} true"
  done
done
check_cmd "panne M09-E40 close (lab/bin/break 09 40 --annuler après réparation)" _m09x_aucune_panne_active E40
