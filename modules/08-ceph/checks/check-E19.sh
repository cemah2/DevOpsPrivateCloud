# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E19.sh — M08-E19 : Retirer et remplacer un OSD
# À lancer depuis adm01. Lecture seule (osd tree, orch osd rm status, health).

# shellcheck source=_m08-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-operationnel.sh"

title "M08-E19 — Retirer et remplacer un OSD"
require_cmd jq

_m08o_arbre="$(_m08o_ceph osd tree --format json)"
_m08o_o="$(jq -c '. as $t | [$t.nodes[] | select(.name == "ceph04") | .children[]] as $ids
  | [$t.nodes[] | select(.type == "osd" and (.id as $i | $ids | index($i)))]' <<<"$_m08o_arbre" 2>/dev/null || echo '[]')"

check_cmd "ceph04 : trois OSD up et in (deux ssd, un hdd)" \
  jq -e 'length == 3 and all(.status == "up" and .reweight == 1) and (map(.device_class) | sort == ["hdd","ssd","ssd"])' <<<"$_m08o_o"
check_cmd "aucun OSD à l'état destroyed dans le cluster" \
  jq -e '[.nodes[] | select(.type == "osd" and .status == "destroyed")] | length == 0' <<<"$_m08o_arbre"
_m08o_rm_vide() {
  local s
  s="$(_m08o_ceph orch osd rm status --format json)"
  [[ -z "$s" ]] || grep -qi 'no osd' <<<"$s" || jq -e 'length == 0' <<<"$s" >/dev/null 2>&1
}
check_cmd "aucune suppression d'OSD en attente (orch osd rm status)" _m08o_rm_vide
_m08o_osd_spec() {
  # Les spécifications OSD sont de nouveau gérées (pas restées en unmanaged après le remplacement).
  _m08o_ceph orch ls osd --format json | jq -e '[.[] | select(.service_name | startswith("osd.")) | select(.unmanaged == true)] | length == 0' >/dev/null
}
check_cmd "spécifications OSD gérées (aucune laissée en unmanaged)" _m08o_osd_spec
check_output "cluster en HEALTH_OK" '^HEALTH_OK' _m08o_ceph health
