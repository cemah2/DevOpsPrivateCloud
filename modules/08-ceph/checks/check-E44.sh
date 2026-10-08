# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c ou sur l'hôte distant
# check-E44.sh — M08-E44 « Sous le capot : où est rangé cet objet ? » : compte rendu présent,
# structuré, commité et cohérent avec le placement réel de l'objet analyse-placement ; cluster
# rendu dans l'état où il a été trouvé (OSD relancé, drapeaux retirés, fichiers de travail effacés).
# Lecture seule.

# shellcheck source=_m08-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-expert.sh"

title "M08-E44 — Sous le capot : le placement d'un objet"
require_cmd git jq ssh

_m08_e44_depot="${WB_DEPOT:-$HOME/medisphere}"
_m08_e44_cr="$_m08_e44_depot/docs/stockage/analyses/placement-objet.md"
check_cmd "compte rendu docs/stockage/analyses/placement-objet.md présent" test -s "$_m08_e44_cr"
check_output "section « Du nom à l'OSD »" '^## .*OSD' cat "$_m08_e44_cr"
check_output "section « Simulations CRUSH »" '^## .*CRUSH' cat "$_m08_e44_cr"
check_output "section « Dans l'OSD »" '^## .*(OSD|BlueStore|objectstore)' cat "$_m08_e44_cr"
check_output "section « Réponses aux questions »" '^## Réponses aux questions' cat "$_m08_e44_cr"
check_cmd "outils cités : ceph osd map, osdmaptool, crushtool, ceph-objectstore-tool" \
  bash -c 'for m in "osd map" osdmaptool crushtool ceph-objectstore-tool; do grep -q -- "$m" "$1" || exit 1; done' _ "$_m08_e44_cr"
check_cmd "compte rendu commité, sans modification en attente" \
  bash -c 'cd "$1" && git ls-files --error-unmatch docs/stockage/analyses/placement-objet.md >/dev/null 2>&1 && [ -z "$(git status --porcelain -- docs/stockage/analyses)" ]' _ "$_m08_e44_depot"

if _m08x_cluster_repond; then
  # Placement réel de l'objet : le PG doit figurer dans le compte rendu.
  _m08_e44_pg="$(_m08x_ceph osd map "$_m08x_pool" analyse-placement -f json 2>/dev/null | jq -r '.pgid // empty')"
  check_cmd "objet analyse-placement présent dans rbd-test" \
    bash -c '[ -n "$1" ]' _ "$(_m08x_ceph_sh 'timeout 30 rados -p rbd-test stat analyse-placement 2>/dev/null')"
  if [[ -n "$_m08_e44_pg" ]]; then
    check_cmd "le PG réel de l'objet ($_m08_e44_pg) figure dans le compte rendu" grep -qF -- "$_m08_e44_pg" "$_m08_e44_cr"
  else
    skip "PG de l'objet dans le compte rendu" "placement illisible"
  fi
  check_cmd "tous les OSD up et in" _m08x_jq '.status.osdmap.num_osds == .status.osdmap.num_up_osds and .status.osdmap.num_osds == .status.osdmap.num_in_osds'
  check_cmd "aucun drapeau noout/norebalance/nodown laissé posé" \
    _m08x_jq '.osd.flags | split(",") | map(select(. == "noout" or . == "norebalance" or . == "nodown" or . == "norecover")) | length == 0'
else
  skip "placement et état du cluster" "les moniteurs ne répondent pas au nœud $_m08x_admin"
fi
for _m08_e44_h in "${_m08x_noeuds[@]}"; do
  check_ssh "$_m08_e44_h : aucune unité ceph masquée ou en échec" "$_m08_e44_h" "sudo -n bash -c $(printf '%q' "$_m08x_cmd_unites_saines")"
  check_ssh "$_m08_e44_h : aucun ceph-objectstore-tool en cours" "$_m08_e44_h" '! pgrep -f "[c]eph-objectstore-tool" >/dev/null'
done
check_cmd "aucune clé ni trousseau dans le compte rendu" bash -c '! grep -Eq "key = |AQ[A-Za-z0-9+/]{30,}==" "$1"' _ "$_m08_e44_cr"
