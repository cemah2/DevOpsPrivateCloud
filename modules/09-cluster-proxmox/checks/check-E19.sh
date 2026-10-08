# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes : pas d'expansion voulue
#
# check-E19.sh — M09-E19 : Mises à jour progressives des nœuds
# À lancer depuis adm01. Lecture seule (pveversion, uname, fichiers de dépôts, ha-manager status, ceph).

# shellcheck source=_m09-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m09-operationnel.sh"

title "M09-E19 — Mises à jour progressives des nœuds"
require_cmd jq

_m09o_versions=""
for _m09o_n in $_M09O_NOEUDS; do
  _m09o_versions+="$(_m09o_hv "$_m09o_n" 'pveversion' | cut -d/ -f2)"$'\n'
  check_ssh "$_m09o_n : tourne sur le noyau le plus récent installé" "$_m09o_n" \
    '[ "$(uname -r)" = "$(ls /boot/vmlinuz-* | sed "s#^/boot/vmlinuz-##" | sort -V | tail -n 1)" ]'
  # Dépôts deb822 : toute strophe qui vise enterprise.proxmox.com doit porter « Enabled: no/false » ;
  # aucune ligne active d'un ancien fichier .list ne doit la viser.
  check_ssh "$_m09o_n : aucun dépôt enterprise actif" "$_m09o_n" \
    'awk "BEGIN{RS=\"\"} /enterprise\.proxmox\.com/ && !/Enabled:[[:space:]]*(no|false)/ {trouve=1} END{exit trouve}" /etc/apt/sources.list.d/*.sources 2>/dev/null
     && ! grep -hsE "^[[:space:]]*deb .*enterprise\.proxmox\.com" /etc/apt/sources.list /etc/apt/sources.list.d/*.list | grep -q .'
  check_ssh "$_m09o_n : dépôts no-subscription de Proxmox VE et de Ceph présents" "$_m09o_n" \
    'grep -hs "pve-no-subscription" /etc/apt/sources.list.d/* | grep -q . \
     && grep -lsE "ceph-(squid|tentacle)" /etc/apt/sources.list.d/* | xargs -r grep -l "no-subscription" | grep -q .'
done
check_output "les trois nœuds ont la même version de pve-manager ($(sort -u <<<"$_m09o_versions" | grep . | tr '\n' ' '))" '^1$' \
  bash -c 'grep . <<<"$1" | sort -u | wc -l' _ "$_m09o_versions"

check_cmd "aucun nœud en maintenance HA" bash -c '[[ -n "$1" ]] && ! grep -qi "maintenance" <<<"$1"' _ \
  "$(_m09o_hv "$(_m09o_noeud)" 'ha-manager status')"
_m09o_d="$(_m09o_ceph 'osd dump')"
check_cmd "Ceph : aucun drapeau noout, ni global ni limité à un nœud" _m09o_json "$_m09o_d" \
  '(.flags | test("noout") | not) and (((.crush_node_flags // {}) | to_entries | map(.value) | flatten | index("noout")) == null)'
check_cmd "Ceph : HEALTH_OK" _m09o_json "$(_m09o_ceph status)" '.health.status == "HEALTH_OK"'

_m09o_pb="$(_m09o_contenu_main plateforme/ansible playbooks/hv-mise-a-jour.yml)"
check_output "plateforme/ansible (main) : playbooks/hv-mise-a-jour.yml" 'hosts:' echo "$_m09o_pb"
check_output "hv-mise-a-jour.yml : un seul nœud à la fois (serial: 1)" '^[[:space:]]*serial:[[:space:]]*1[[:space:]]*$' echo "$_m09o_pb"
check_output "hv-mise-a-jour.yml : mode maintenance HA" 'node-maintenance' echo "$_m09o_pb"
check_output "hv-mise-a-jour.yml : mise à jour complète (dist / full-upgrade)" '(upgrade:[[:space:]]*(dist|full)|full-upgrade|dist-upgrade)' echo "$_m09o_pb"
