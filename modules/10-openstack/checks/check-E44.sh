# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E44.sh — M10-E44 « Sous le capot : la vie d'un server create » : compte rendu présent,
# structuré, commité, sans jeton ; instance de traçage supprimée ; journalisation de débogage
# revenue à la normale. Lecture seule.
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c ou à distance

# shellcheck source=_m10-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-expert.sh"

title "M10-E44 — Sous le capot : la vie d'un server create"
require_cmd git openstack ssh

_m10_e44_rel="docs/cloud/analyses/vie-d-un-server-create.md"
_m10_e44_cr="$_m10x_depot/$_m10_e44_rel"
check_cmd "compte rendu $_m10_e44_rel présent" test -s "$_m10_e44_cr"
for _m10_e44_s in "Requête et identifiant" "Plan de contrôle" "Réseau" "Hyperviseur" "Réponses aux questions"; do
  check_output "section « $_m10_e44_s »" "^## .*$_m10_e44_s" cat "$_m10_e44_cr"
done
check_cmd "étapes citées : identifiant req-, scheduler, Placement, conductor, ovn-nbctl, ovn-sbctl, virsh" \
  bash -c 'for m in "req-[0-9a-f]{8}" "nova-scheduler" "[Pp]lacement" "nova-conductor" "ovn-nbctl" "ovn-sbctl" "virsh"; do grep -Eq -- "$m" "$1" || exit 1; done' _ "$_m10_e44_cr"
check_cmd "aucun jeton (X-Auth-Token, jeton fernet gAAAAA…) dans le compte rendu" \
  bash -c '! grep -Eq "gAAAAA[A-Za-z0-9_-]{20,}|X-Auth-Token: [^*{ ]" "$1"' _ "$_m10_e44_cr"
check_cmd "compte rendu commité, sans modification en attente" _m10x_commite "$_m10_e44_rel"
check_cmd "instance de traçage m10-e44-trace supprimée" \
  bash -c '[ -z "$(timeout 60 openstack --os-cloud "$1" server list --name "^m10-e44-" -f value -c ID 2>/dev/null)" ]' _ "$_m10x_cloud_projet"
check_ssh "$_m10x_ctl : journalisation de débogage de nova-api et nova-scheduler désactivée" "$_m10x_ctl" \
  '! sudo -n grep -hEi "^[[:space:]]*debug[[:space:]]*=[[:space:]]*true" /etc/kolla/nova-api/nova.conf /etc/kolla/nova-scheduler/nova.conf /etc/kolla/nova-conductor/nova.conf 2>/dev/null | grep -q .'
