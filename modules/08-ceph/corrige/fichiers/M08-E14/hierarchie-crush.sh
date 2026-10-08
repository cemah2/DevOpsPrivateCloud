#!/usr/bin/env bash
# hierarchie-crush.sh — M08-E14 (PLAT-924) : hiérarchie datacenter/baies, règles par classe,
# affectation des pools UN PAR UN avec attente de HEALTH_OK. Depuis adm01. Idempotent.
# ⚠️ Déplace des données (déplacement des hôtes, changement de règle des pools) : lis avant de lancer,
# et lance-le dans un créneau où une latence plus élevée est acceptable.
# shellcheck disable=SC2029  # développement local voulu dans les commandes ssh
set -euo pipefail

ADMIN=${WB_CEPH_ADMIN:-ceph01}
c() { ssh -o BatchMode=yes "$ADMIN" "sudo ceph $(printf '%q ' "$@")" 2>/dev/null; }

attendre_sante() {
  local i
  for i in $(seq 1 120); do
    if c health | grep -q '^HEALTH_OK'; then return 0; fi
    (( i % 6 == 0 )) && echo "  … $(c -s --format json | jq -r '.pgmap | "\(.misplaced_ratio // 0 | . * 100 | floor) % misplaced, \(.degraded_ratio // 0 | . * 100 | floor) % degraded"')"
    sleep 10
  done
  echo "HEALTH_OK non atteint en 20 minutes : arrêt (ceph health detail)" >&2; exit 1
}
existe() { c osd crush tree --format json | jq -e --arg n "$1" '.nodes[] | select(.name == $n)' >/dev/null; }
parent() { c osd tree --format json | jq -r --arg n "$1" '. as $t | ($t.nodes[] | select(.name == $n) | .id) as $id
  | [$t.nodes[] | select((.children // []) | index($id)) | .name][0] // ""'; }

attendre_sante
echo "== Hiérarchie"
existe par1 || c osd crush add-bucket par1 datacenter
[[ "$(parent par1)" == default ]] || c osd crush move par1 root=default
for b in a b c; do
  existe "par1-baie-$b" || c osd crush add-bucket "par1-baie-$b" rack
  [[ "$(parent "par1-baie-$b")" == par1 ]] || c osd crush move "par1-baie-$b" datacenter=par1
done
declare -A BAIE=([ceph01]=par1-baie-a [ceph02]=par1-baie-b [ceph03]=par1-baie-c)
for h in ceph01 ceph02 ceph03; do
  if [[ "$(parent "$h")" != "${BAIE[$h]}" ]]; then
    echo "  $h → ${BAIE[$h]}"
    c osd crush move "$h" "rack=${BAIE[$h]}"
    attendre_sante
  fi
done
c osd crush tree

echo "== Règles"
for cl in ssd hdd; do
  c osd crush rule ls | grep -qx "$cl-baie" || c osd crush rule create-replicated "$cl-baie" default rack "$cl"
done
ID_SSD="$(c osd crush rule dump ssd-baie --format json | jq -r .rule_id)"

echo "== Pools répliqués → ssd-baie (un par un)"
# Petits pools d'abord (métadonnées), gros ensuite.
ordre='.mgr cephfs.cephfs.meta .rgw.root default.rgw.log default.rgw.control default.rgw.meta
default.rgw.buckets.index default.rgw.buckets.non-ec .nfs rbd-test cephfs.cephfs.data default.rgw.buckets.data'
pools="$(c osd pool ls detail --format json)"
for p in $ordre; do
  info="$(jq -c --arg p "$p" '.[] | select(.pool_name == $p and .type == 1)' <<<"$pools")"   # type 1 = répliqué
  [[ -n "$info" ]] || continue
  if [[ "$(jq -r .crush_rule <<<"$info")" != "$ID_SSD" ]]; then
    echo "  $p → ssd-baie"
    c osd pool set "$p" crush_rule ssd-baie
    attendre_sante
  fi
done
# Pool répliqué oublié de la liste ?
c osd pool ls detail --format json | jq -r --argjson id "$ID_SSD" '.[] | select(.type == 1 and .crush_rule != $id) | "  ATTENTION : \(.pool_name) n'\''est pas sur ssd-baie"'

echo "== Règle par défaut des nouveaux pools : $ID_SSD (ssd-baie)"
c config set global osd_pool_default_crush_rule "$ID_SSD"
c config get global osd_pool_default_crush_rule
