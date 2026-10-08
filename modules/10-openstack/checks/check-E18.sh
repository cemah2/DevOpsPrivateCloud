# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes et filtres entre apostrophes sont évalués ailleurs
#
# check-E18.sh — M10-E18 : Métadonnées et cloud-init dans OpenStack
# À lancer depuis adm01, e18-vm démarrée avec son IP flottante. Lecture seule ; SSH dans e18-vm (debian).

# shellcheck source=_m10-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m10-operationnel.sh"

title "M10-E18 — Métadonnées et cloud-init dans OpenStack"
require_cmd openstack jq ssh

check_cmd "dépôt (main) : nova/vendordata.json, JSON valide avec une clé cloud-init" \
  bash -c 'jq -e "has(\"cloud-init\")" <<<"$1" >/dev/null' _ "$(_m10o_contenu_main "$_M10O_PROJET_OS" etc/kolla/config/nova/vendordata.json)"
check_cmd "osctl01 (généré) : vendordata.json présent pour nova-metadata" \
  bash -c 'jq -e "has(\"cloud-init\")" <<<"$1" >/dev/null' _ "$(_m10o_conf_noeud "$_M10O_CTL" /etc/kolla/nova-metadata/vendordata.json)"

_m10o_vm="$(_m10o_serveur e18-vm)"
_m10o_fip="$(_m10o_ip_flottante "$_m10o_vm")"
if [[ -n "$_m10o_fip" ]]; then
  check_ssh_output_i() { local d="$1" r="$2" c="$3" o; o="$(_m10o_ssh_instance "$_m10o_fip" "$c" 2>&1 || true)"; if grep -Eq -- "$r" <<<"$o"; then _ok "$d"; else _ko "$d"; fi; }
  check_ssh_output_i "e18-vm : cloud-init a terminé sans erreur" '^status: done' 'cloud-init status'
  check_ssh_output_i "e18-vm : /etc/medisphere/role contient web" '^web$' 'cat /etc/medisphere/role'
  check_ssh_output_i "e18-vm : chrony a 10.10.52.1 pour source (données fournisseur)" '10\.10\.52\.1\b' 'chronyc -n sources'
else
  _ko "e18-vm : introuvable, ou sans IP flottante dans 10.10.52.0/24"
fi

_m10o_cd="$(_m10o_serveur e18-cd)"
check_cmd "e18-cd : ACTIVE, avec config drive" \
  jq -e '.status == "ACTIVE" and ((.config_drive | tostring | ascii_downcase) == "true")' <<<"$_m10o_cd"
check_cmd "e18-cd : adresse reçue dans 192.168.180.0/24 (réseau e18-sans-dhcp)" \
  jq -e '.addresses | tostring | test("e18-sans-dhcp.*192\\.168\\.180\\.")' <<<"$_m10o_cd"
check_output "e18-sans-dhcp : sous-réseau sans DHCP" '^False$' \
  _m10o_os subnet list --network e18-sans-dhcp -f value -c 'DHCP' --long
for _m10o_h in $_M10O_CALCULS; do
  check_ssh "$_m10o_h : neutron_ovn_metadata_agent en marche" "$_m10o_h" \
    'sudo -n docker ps --filter name=^neutron_ovn_metadata_agent$ --filter status=running -q | grep -q .'
done
