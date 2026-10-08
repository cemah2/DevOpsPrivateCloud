# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E16.sh — M10-E16 : Octavia : répartiteurs de charge à la demande
# À lancer depuis adm01. Lecture seule : API (cloud du projet mediagenda-dev pour les objets Octavia), GitLab, HTTP.

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E16 — Octavia : répartiteurs de charge à la demande"
require_cmd openstack jq curl

_m10o_g="$(_m10o_globals)"
check_cmd "globals.yml (main) : Octavia activé" _m10o_globals_vaut "$_m10o_g" enable_octavia 'yes|true|True'
check_cmd "globals.yml (main) : seul le fournisseur ovn est déclaré" \
  _m10o_globals_vaut "$_m10o_g" octavia_provider_drivers 'ovn:OVN provider'
_m10o_prov="$(_m10o_os loadbalancer provider list -f value -c name || true)"
check_cmd "fournisseurs d'Octavia : ovn présent, amphora absent" \
  bash -c 'grep -qx ovn <<<"$1" && ! grep -qx amphora <<<"$1"' _ "$_m10o_prov"

_m10o_dev="$(_m10o_projet_id mediagenda-dev)"
check_output "mediagenda-dev : quota de répartiteurs posé (pas illimité)" '^[0-9]+$' \
  bash -c '[[ -n "$1" ]] && openstack --os-cloud "$2" loadbalancer quota show -f json "$1" 2>/dev/null | jq -r ".load_balancer // .loadbalancer | select(. != -1 and . != null)"' \
  _ "$_m10o_dev" "$_M10O_CLOUD"

if _m10o_cloud_existe "$_M10O_CLOUD_DEV"; then
  _m10o_lb="$(_m10o_osc "$_M10O_CLOUD_DEV" loadbalancer show -f json lb-e16 || true)"
  check_cmd "lb-e16 : fournisseur ovn, ACTIVE et ONLINE" \
    jq -e '.provider == "ovn" and .provisioning_status == "ACTIVE" and .operating_status == "ONLINE"' <<<"$_m10o_lb"
  check_cmd "lb-e16 : un écouteur TCP sur le port 80" \
    jq -e 'map(select(.protocol == "TCP" and .protocol_port == 80)) | length >= 1' \
    <<<"$(_m10o_osc "$_M10O_CLOUD_DEV" loadbalancer listener list --loadbalancer lb-e16 -f json || echo '[]')"
  _m10o_pool="$(_m10o_osc "$_M10O_CLOUD_DEV" loadbalancer pool list --loadbalancer lb-e16 -f json | jq -r 'first | .id // empty' 2>/dev/null || true)"
  _m10o_pool_json="$( [[ -n "$_m10o_pool" ]] && _m10o_osc "$_M10O_CLOUD_DEV" loadbalancer pool show -f json "$_m10o_pool" || true)"
  check_cmd "pool : algorithme SOURCE_IP_PORT, protocole TCP" \
    jq -e '.lb_algorithm == "SOURCE_IP_PORT" and .protocol == "TCP"' <<<"$_m10o_pool_json"
  check_output "pool : deux membres" '^2$' \
    bash -c '[[ -n "$1" ]] && openstack --os-cloud "$2" loadbalancer member list -f value -c id "$1" 2>/dev/null | wc -l' _ "$_m10o_pool" "$_M10O_CLOUD_DEV"
  _m10o_hm="$(jq -r '.healthmonitor_id // empty' <<<"$_m10o_pool_json" 2>/dev/null || true)"
  check_output "pool : contrôle de santé TCP" '^TCP$' \
    bash -c '[[ -n "$1" ]] && openstack --os-cloud "$2" loadbalancer healthmonitor show -f value -c type "$1" 2>/dev/null' _ "$_m10o_hm" "$_M10O_CLOUD_DEV"
  _m10o_vip="$(jq -r '.vip_port_id // empty' <<<"$_m10o_lb" 2>/dev/null || true)"
  _m10o_fip="$( [[ -n "$_m10o_vip" ]] && _m10o_os floating ip list --port "$_m10o_vip" -f value -c 'Floating IP Address' | head -n 1 || true)"
  if [[ -n "$_m10o_fip" ]]; then
    check_http "http://$_m10o_fip/ (IP flottante de lb-e16) répond depuis adm01" "http://$_m10o_fip/" 200
  else
    _ko "lb-e16 : aucune IP flottante associée au port de l'adresse virtuelle"
  fi
else
  _ko "cloud $_M10O_CLOUD_DEV absent de clouds.yaml (E05) : impossible de lire les objets du projet"
fi
