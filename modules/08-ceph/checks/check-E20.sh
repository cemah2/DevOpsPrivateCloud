# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E20.sh — M08-E20 : Capacité, quotas et seuils de remplissage
# À lancer depuis adm01. Lecture seule (osd dump, pool ls detail, config get, auth get).

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E20 — Capacité, quotas et seuils de remplissage"
require_cmd jq

_m08o_dump="$(_m08o_ceph osd dump --format json)"
_m08o_pools="$(_m08o_ceph osd pool ls detail --format json)"

check_cmd "nearfull ≤ 0,75 et backfillfull ≤ 0,85" \
  jq -e '.nearfull_ratio <= 0.7501 and .backfillfull_ratio <= 0.8501' <<<"$_m08o_dump"
check_cmd "seuils dans l'ordre nearfull < backfillfull < full" \
  jq -e '.nearfull_ratio < .backfillfull_ratio and .backfillfull_ratio < .full_ratio' <<<"$_m08o_dump"
for _m08o_p in rbd-test rbd-ec-donnees; do
  check_cmd "pool $_m08o_p : quota en octets" \
    jq -e --arg p "$_m08o_p" '.[] | select(.pool_name == $p) | (.quota_max_bytes // 0) > 0' <<<"$_m08o_pools"
done
check_cmd "pool rbd-test : taille cible pour l'autoscaler" \
  jq -e '.[] | select(.pool_name == "rbd-test") | ((.options.target_size_ratio // 0) > 0 or (.options.target_size_bytes // 0) > 0)' <<<"$_m08o_pools"
check_cmd "pool essai-plein supprimé" jq -e '[.[] | select(.pool_name == "essai-plein")] | length == 0' <<<"$_m08o_pools"
check_output "mon_allow_pool_delete vaut false" '^false$' bash -c '_m="$1"; tr -d "[:space:]" <<<"$_m"' _ \
  "$(_m08o_ceph config get mon mon_allow_pool_delete)"
check_cmd "client.rapport : lecture seule (mon et mgr « allow r », aucun droit OSD)" \
  jq -e '.[0].caps | (.mon == "allow r") and (.mgr == "allow r") and (has("osd") | not) and (has("mds") | not)' \
  <<<"$(_m08o_ceph auth get client.rapport --format json)"
check_output "cluster sans alerte de remplissage (FULL, NEARFULL)" '^ok$' bash -c \
  'grep -qE "(POOL|OSD)_(NEAR|BACKFILL)?FULL" <<<"$1" && echo alerte || echo ok' _ "$(_m08o_ceph health detail)"
