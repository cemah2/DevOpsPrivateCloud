# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E20.sh — M10-E20 : Kolla au quotidien : surcharges, reconfiguration, journaux
# À lancer depuis adm01. Lecture seule : configuration générée et conteneurs des nœuds, Placement, GitLab.

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E20 — Kolla au quotidien : surcharges, reconfiguration, journaux"
require_cmd openstack jq

_m10o_surcharge_hote() { _m10o_arbre_main "$_M10O_PROJET_OS" etc/kolla/config/nova | grep -q '^etc/kolla/config/nova/oscmp02/'; }
check_cmd "dépôt (main) : une surcharge propre à l'hôte oscmp02 sous etc/kolla/config/nova/oscmp02/" _m10o_surcharge_hote

for _m10o_h in $_M10O_CALCULS; do
  _m10o_c="$(_m10o_conf_noeud "$_m10o_h" /etc/kolla/nova-compute/nova.conf)"
  check_cmd "$_m10o_h (généré) : reserved_host_memory_mb = 2048" _m10o_ini_vaut "$_m10o_c" reserved_host_memory_mb '2048'
  if [[ "$_m10o_h" == oscmp02 ]]; then
    check_cmd "$_m10o_h (généré) : cpu_allocation_ratio = 2.0" _m10o_ini_vaut "$_m10o_c" cpu_allocation_ratio '2(\.0+)?'
  else
    check_cmd "$_m10o_h (généré) : cpu_allocation_ratio n'est pas 2.0" \
      bash -c '[[ -n "$1" ]] && ! grep -Eq "^[[:space:]]*cpu_allocation_ratio[[:space:]]*=[[:space:]]*2(\.0+)?[[:space:]]*$" <<<"$1"' _ "$_m10o_c"
  fi
  _m10o_u="$(_m10o_rp_uuid "$_m10o_h")"
  check_output "Placement $_m10o_h : MEMORY_MB réservé 2048" '^2048$' \
    bash -c '[[ -n "$1" ]] && openstack --os-cloud "$2" resource provider inventory show -f value -c reserved "$1" MEMORY_MB 2>/dev/null' _ "$_m10o_u" "$_M10O_CLOUD"
  _m10o_ratio="$( [[ -n "$_m10o_u" ]] && _m10o_os resource provider inventory show -f value -c allocation_ratio "$_m10o_u" VCPU || true)"
  if [[ "$_m10o_h" == oscmp02 ]]; then
    check_output "Placement $_m10o_h : ratio VCPU 2.0" '^2(\.0+)?$' echo "$_m10o_ratio"
  else
    check_output "Placement $_m10o_h : ratio VCPU différent de 2.0 (${_m10o_ratio:-illisible})" '^([013-9]|2\.0*[1-9])' echo "$_m10o_ratio"
  fi
done

check_cmd "neutron-server (généré) : mode debug désactivé" \
  bash -c '[[ -n "$1" ]] && ! grep -Eiq "^[[:space:]]*debug[[:space:]]*=[[:space:]]*true" <<<"$1"' _ "$(_m10o_conf_noeud "$_M10O_CTL" /etc/kolla/neutron-server/neutron.conf)"
for _m10o_h in $_M10O_CTL $_M10O_CALCULS; do
  check_ssh "$_m10o_h : aucun conteneur unhealthy" "$_m10o_h" \
    'sudo -n docker ps -q >/dev/null && [ -z "$(sudo -n docker ps --filter health=unhealthy -q)" ]'
done
check_output "README de plateforme/openstack (main) : section « Changer la configuration »" '^#+ +Changer la configuration' \
  _m10o_contenu_main "$_M10O_PROJET_OS" README.md
