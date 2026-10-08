# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E36.sh — M08-E36 « Panne : des PG restent inactifs » : tous les PG sont actifs et propres,
# le pool rbd-test a une réplication cohérente avec le cluster, aucune règle ni classe impossible.
# Lecture seule.
# shellcheck disable=SC2016  # filtres jq entre apostrophes

# shellcheck source=_m08-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-expert.sh"

title "M08-E36 — Les PG sont actifs"
require_cmd jq ssh

if _m08x_cluster_repond; then
  check_cmd "aucun PG inactif (PG_AVAILABILITY absent)" _m08x_jq '.health.checks | has("PG_AVAILABILITY") | not'
  check_cmd "tous les PG sont active+clean" \
    _m08x_jq '[.status.pgmap.pgs_by_state[] | select(.state_name | startswith("active+clean") | not)] | length == 0'
  check_cmd "rbd-test : size 3 (trois hôtes, domaine de panne host)" \
    _m08x_jq '.pools[] | select(.pool_name == "rbd-test") | .size == 3'
  check_cmd "rbd-test : min_size 2" _m08x_jq '.pools[] | select(.pool_name == "rbd-test") | .min_size == 2'
  check_cmd "rbd-test : sa règle CRUSH part de la racine « default »" \
    _m08x_jq '(.pools[] | select(.pool_name == "rbd-test") | .crush_rule) as $r
      | .rules[] | select(.rule_id == $r) | [.steps[] | select(.op == "take") | .item_name] | all(startswith("default"))'
  check_cmd "aucun OSD dans une classe sans équivalent matériel (nvme)" _m08x_jq '.classes | index("nvme") | not'
  check_cmd "aucun pool ne vise une règle CRUSH de racine vide (par2)" \
    _m08x_jq '[.rules[] | select([.steps[] | select(.op == "take") | .item_name] | any(startswith("par2")))] | length == 0'
else
  skip "état des PG" "les moniteurs ne répondent pas au nœud $_m08x_admin"
fi
check_cmd "panne M08-E36 close (lab/bin/break 08 36 --annuler après réparation)" _m08x_aucune_panne_active E36
