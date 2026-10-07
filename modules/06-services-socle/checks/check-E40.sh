# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E40.sh — M06-E40 « Panne : l'inventaire NetBox ne renvoie plus d'hôtes » : l'inventaire
# NetBox contient tout le socle (au moins les hôtes que l'inventaire Proxmox met dans socle), les
# données NetBox dont il dépend sont saines, et la copie de travail est propre. Lecture seule.

# shellcheck source=_m06-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m06-expert.sh"

title "M06-E40 — Inventaire Ansible depuis NetBox"
require_cmd jq git

_m06_e40_inv="$(_m06x_inv_netbox 2>/dev/null || true)"
check_cmd "inventaire NetBox présent (plugin netbox.netbox.nb_inventory)" test -n "$_m06_e40_inv"
_m06_e40_nb='{}'
_m06_e40_px='{}'
if [[ -n "$_m06_e40_inv" ]]; then
  _m06_e40_nb="$(_m06x_ansible ansible-inventory -i "$_m06_e40_inv" --list 2>/dev/null)" || _m06_e40_nb='{}'
fi
_m06_e40_px="$(_m06x_ansible ansible-inventory -i inventories/lab/proxmox.yml --list 2>/dev/null)" || _m06_e40_px='{}'

_m06_e40_couvre() {
  local h n=0
  [[ -n "$(_m06x_hotes_groupe "$_m06_e40_nb" socle)" ]] || return 1
  while IFS= read -r h; do
    [[ -n "$h" ]] || continue
    n=$((n + 1))
    _m06x_hotes_groupe "$_m06_e40_nb" socle | grep -qx "$h" || return 1
  done < <(_m06x_hotes_groupe "$_m06_e40_px" socle)
  ((n > 0))
}
_m06_e40_ip() {
  jq -e --arg ip 10.10.20.13 '._meta.hostvars.nbx01.ansible_host == $ip' >/dev/null <<<"$_m06_e40_nb"
}
_m06_e40_tag() { netbox_api 'extras/tags/?slug=socle' | jq -e '.count == 1' >/dev/null; }
_m06_e40_statuts() {
  netbox_api 'virtualization/virtual-machines/?tag=socle&limit=0' \
    | jq -e '.count > 0 and ([.results[].status.value] | all(. == "active"))' >/dev/null
}
_m06_e40_vm() {
  [[ -n "$_m06_e40_inv" ]] && ! grep -Eq '^virtual_machines:[[:space:]]*(false|no|False)' "$_m06x_ansible_dir/$_m06_e40_inv"
}

check_cmd "groupe socle de l'inventaire NetBox ⊇ groupe socle de l'inventaire Proxmox" _m06_e40_couvre
check_cmd "nbx01 : ansible_host = 10.10.20.13 (IP primaire NetBox)" _m06_e40_ip
check_cmd "NetBox : étiquette socle présente (slug socle)" _m06_e40_tag
check_cmd "NetBox : toutes les VMs étiquetées socle au statut active" _m06_e40_statuts
check_cmd "inventaire NetBox : les machines virtuelles sont incluses" _m06_e40_vm
check_output "copie de travail ~/src/ansible propre" '^$' git -C "$_m06x_ansible_dir" status --porcelain
check_cmd "panne M06-E40 close (lab/bin/break 06 40 --annuler après réparation)" _m06x_aucune_panne_active E40
