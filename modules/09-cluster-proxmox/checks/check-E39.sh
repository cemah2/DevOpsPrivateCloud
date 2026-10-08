# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur le nœud distant
# check-E39.sh — M09-E39 « Panne : les VMs se figent » : Ceph hyperconvergé HEALTH_OK, 6 OSD up/in,
# tous les PG actifs, pool de ceph-vm en 3/2, pas de drapeau oublié, jumbo frames de bout en bout sur
# les réseaux public et cluster de Ceph. Lecture seule.

# shellcheck source=_m09-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-expert.sh"

title "M09-E39 — Ceph hyperconvergé sain"
require_cmd ssh

_m09_e39_h="$(_m09x_un_noeud)"
_m09_e39_c="$(_m09x_cible "$_m09_e39_h")"
check_ssh_output "Ceph : HEALTH_OK" "$_m09_e39_c" '^HEALTH_OK' 'timeout 20 ceph health'
check_ssh_output "Ceph : 6 OSD, tous up et in" "$_m09_e39_c" '6 osds: 6 up[^,]*, 6 in' 'timeout 20 ceph osd stat'
check_ssh "Ceph : tous les PG active+clean" "$_m09_e39_c" '
  s=$(timeout 20 ceph pg stat) || exit 1
  t=$(sed -nE "s/^([0-9]+) pgs: .*/\1/p" <<<"$s")
  a=$(sed -nE "s/^[0-9]+ pgs: ([^;]*);.*/\1/p" <<<"$s" | tr "," "\n" | awk "\$2 ~ /^active\\+clean/ { n += \$1 } END { print n + 0 }")
  [ -n "$t" ] && [ "$t" = "$a" ]'
check_ssh "Ceph : aucun drapeau noout/norecover/nobackfill/pause oublié" "$_m09_e39_c" \
  '! timeout 20 ceph osd dump | grep -E "^flags" | grep -Eq "noout|norecover|nobackfill|norebalance|pause"'
check_ssh "pool du stockage ceph-vm : size 3, min_size 2" "$_m09_e39_c" '
  p=$(awk "/^[a-z]+: /{d=(\$2==\"ceph-vm\")} d&&\$1==\"pool\"{print \$2; exit}" /etc/pve/storage.cfg); p=${p:-rbd}
  [ "$(ceph osd pool get "$p" size)" = "size: 3" ] && [ "$(ceph osd pool get "$p" min_size)" = "min_size: 2" ]'
for _m09_e39_n in "${_m09x_noeuds[@]}"; do
  check_ssh "$_m09_e39_n : OSD actifs et activés au démarrage" "$(_m09x_cible "$_m09_e39_n")" '
    ids=$(ceph osd ls-tree "$(hostname -s)") && [ -n "$ids" ] || exit 1
    for i in $ids; do systemctl is-active -q ceph-osd@$i && systemctl is-enabled -q ceph-osd@$i || exit 1; done'
  check_cmd "$_m09_e39_n : aucun filtrage parasite (table $_m09x_table absente)" _m09x_pas_de_table "$_m09_e39_n"
done
for _m09_e39_d in hv02 hv03; do
  check_ssh "hv01 → $_m09_e39_d : trames de 9000 octets sans fragmentation (Ceph public et cluster)" "$(_m09x_cible hv01)" \
    "ping -M do -s 8972 -c 2 -W 2 ${_m09x_stopub[$_m09_e39_d]} >/dev/null && ping -M do -s 8972 -c 2 -W 2 ${_m09x_stoclu[$_m09_e39_d]} >/dev/null"
done
check_cmd "runbook RB-094 (PG inactifs, E/S bloquées) présent et commité" \
  bash -c 'f=$(cd "$1" && ls docs/virtualisation/runbooks/RB-094*.md 2>/dev/null | head -n 1) && [ -n "$f" ] && cd "$1" && git ls-files --error-unmatch "$f" >/dev/null 2>&1' _ "$_m09x_depot"
check_cmd "panne M09-E39 close (lab/bin/break 09 39 --annuler après réparation)" _m09x_aucune_panne_active E39
