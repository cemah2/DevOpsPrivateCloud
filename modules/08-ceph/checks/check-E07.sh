# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E07.sh — M08-E07 : Lire l'état d'un cluster
# À lancer depuis adm01. Lecture seule : commandes « ceph » d'observation sur le nœud _admin,
# API GitLab en GET (fiche d'astreinte dans plateforme/medisphere).

# shellcheck source=_m08-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m08-decouverte.sh"

title "M08-E07 — Lire l'état d'un cluster"
require_cmd jq curl

# --- 1. Le cluster est revenu à l'état sain après les manipulations ---------------------------------
_m08d_e07_dump="$(_m08d_ceph "osd dump -f json")"
check_cmd "Aucun drapeau d'exploitation oublié (noout, noin, nodown, noup, norebalance, nobackfill, norecover, pause)" \
  _m08d_json "$_m08d_e07_dump" \
  '(.flags_set // (.flags | split(","))) as $f
   | [$f[] | select(IN("noout", "noin", "nodown", "noup", "norebalance", "nobackfill", "norecover", "pauserd", "pausewr"))] | length == 0'
check_cmd "Neuf OSD « up » et « in », poids de réplication intact (reweight 1)" _m08d_json "$_m08d_e07_dump" \
  '(.osds | length) == 9 and all(.osds[]; .up == 1 and .in == 1 and .weight == 1)'
check_cmd "Démons OSD tous en fonctionnement pour cephadm" _m08d_json "$(_m08d_ceph "orch ps --daemon-type osd -f json")" \
  'length == 9 and all(.[]; .status_desc == "running")'
check_cmd "Aucune alerte « mise en sourdine » qui masquerait un problème" _m08d_json "$(_m08d_ceph "health -f json")" \
  '[(.mutes // [])[]] | length == 0'
check_cmd "Aucun plantage de démon non acquitté (crash ls-new)" _m08d_json "$(_m08d_ceph "crash ls-new -f json")" 'length == 0'
check_output "Cluster en HEALTH_OK" '^HEALTH_OK$' _m08d_sante

# --- 2. La fiche d'astreinte ------------------------------------------------------------------------------
_m08d_e07_fiche="$(_m08d_contenu_main plateforme/medisphere docs/stockage/lire-etat-ceph.md)"
check_cmd "plateforme/medisphere (main) : docs/stockage/lire-etat-ceph.md" bash -c '[[ -n "$1" ]]' _ "$_m08d_e07_fiche"
for _m08d_e07_mot in "ceph health detail" "ceph osd tree" "noout" "active+clean" "ceph orch ps"; do
  check_cmd "Fiche : traite « $_m08d_e07_mot »" bash -c 'grep -qF -- "$2" <<<"$1"' _ "$_m08d_e07_fiche" "$_m08d_e07_mot"
done
