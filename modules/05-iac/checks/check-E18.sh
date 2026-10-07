# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c ou l'hôte distant
#
# check-E18.sh — M05-E18 : Dépendances et cycle de vie des ressources
# Lecture seule : état et code de lab-m05, Proxmox (root sur pve01).

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E18 — Dépendances et cycle de vie des ressources"
require_cmd jq tofu

check_cmd "état lab-m05 : terraform_data qui porte la génération de la VM jetable" \
  _m05o_a_adresse "$_m05o_lab" '^terraform_data\.'
check_cmd "état lab-m05 : VM 2054 (m05-jetable)" _m05o_a_vmid "$_m05o_lab" 2054
check_cmd "code : recréation déclenchée par la génération (replace_triggered_by)" \
  _m05o_code "$_m05o_lab" 'replace_triggered_by[[:space:]]*=[[:space:]]*\[[^]]*terraform_data\.'
check_cmd "code : une précondition et une postcondition sur la VM jetable" \
  bash -c 'grep -qs "precondition" "$1"/*.tf && grep -qs "postcondition" "$1"/*.tf' _ "$_m05o_lab"
check_cmd "code : pas de depends_on entre ressources déjà reliées par une référence" \
  bash -c '! grep -Eqs "depends_on[[:space:]]*=[[:space:]]*\[[^]]*data\.proxmox_virtual_environment_vms" "$1"/*.tf' _ "$_m05o_lab"

_m05o_gen="$(sed -nE 's/^[[:space:]]*generation_jetable[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$_m05o_lab"/*.tfvars 2>/dev/null | tail -n 1 || true)"
_m05o_c="$(_m05o_qm 2054)"
check_output "VM 2054 : nom m05-jetable" '^name: m05-jetable$' printf '%s\n' "$_m05o_c"
check_cmd "VM 2054 : sa description porte la génération déclarée (${_m05o_gen:-?})" \
  bash -c '[ -n "$2" ] && grep -E "^description:" <<<"$1" | grep -q -- "$2"' _ "$_m05o_c" "$_m05o_gen"
check_ssh "VM 2054 : bail DHCP du VLAN 99 (vu par l'agent QEMU)" "$WB_PVE_HOST" \
  'qm guest cmd 2054 network-get-interfaces | grep -q "\"10\.10\.99\.[0-9]*\""'
check_cmd "lab-m05 : plan sans aucun changement" _m05o_plan_vide "$_m05o_lab"

_m05o_destruction_refusee() {
  local sortie
  if sortie="$(_m05o_tofu "$_m05o_socle" plan -destroy -lock=false -refresh=false -no-color -input=false 2>&1)"; then
    return 1
  fi
  grep -q "cannot be destroyed" <<<"$sortie"
}
check_cmd "socle : la destruction reste refusée (prevent_destroy)" _m05o_destruction_refusee
