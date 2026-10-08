# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
#
# check-E28.sh — M09-E28 « Monter Ceph de Squid à Tentacle »
# Lecture seule : ceph versions / osd dump / mon dump / health (JSON), dépôts APT des nœuds,
# instantanés des VMs 2091-2093 sur pve01 (qm listsnapshot), GitLab.

# shellcheck source=_m09-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-production.sh"

title "M09-E28 — Monter Ceph de Squid à Tentacle"
require_cmd jq ssh
_m09p_charger

title "Versions"
check_cmd "tous les démons Ceph en 20.2.x (aucun Squid)" _m09p_ceph_jq versions \
  '(.overall | keys | length) > 0 and (.overall | keys | all(test(" 20\\.2\\.")))'
check_cmd "MON, MGR et OSD présents dans le relevé" _m09p_ceph_jq versions \
  '(.mon | length) > 0 and (.mgr | length) > 0 and (.osd | length) > 0'
check_cmd "require_osd_release = tentacle" _m09p_ceph_jq "osd dump" '.require_osd_release == "tentacle"'
check_cmd "min_mon_release = 20 (tentacle)" _m09p_ceph_jq "mon dump" '(.min_mon_release | tostring) == "20"'

title "État"
check_cmd "drapeau noout retiré" _m09p_ceph_jq "osd dump" '((.flags // "") | split(",") | index("noout")) == null'
check_cmd "Ceph en HEALTH_OK" _m09p_ceph_ok
for _m09_e28_n in "${_M09P_NOEUDS[@]}"; do
  check_ssh "$_m09_e28_n : dépôt ceph-tentacle, plus aucun dépôt ceph-squid" "$_m09_e28_n" \
    'grep -rqs "ceph-tentacle" /etc/apt/sources.list.d/ && ! grep -rqs "ceph-squid" /etc/apt/sources.list /etc/apt/sources.list.d/'
  _m09_e28_id="${_M09P_VMID[$_m09_e28_n]}"
  check_ssh "VM $_m09_e28_id ($_m09_e28_n) : aucun instantané de filet restant" "$WB_PVE_HOST" \
    "! qm listsnapshot $_m09_e28_id | grep -v 'current' | grep -q ."
done

title "Code et documentation"
check_cmd "plateforme/ansible : playbooks/ceph-squid-vers-tentacle.yml sur main" \
  _m09p_fichier_existe plateforme/ansible playbooks/ceph-squid-vers-tentacle.yml
check_cmd "fiche CHG-1054 sur main (docs/virtualisation/changements/)" _m09p_doc changements CHG-1054
