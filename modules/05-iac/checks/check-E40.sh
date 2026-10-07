# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E40.sh — M05-E40 « Panne : l'état ne correspond plus à la réalité » : toute VM étiquetée
# env-m05 dans Proxmox est gérée par l'état envs/lab-m05 (et réciproquement), le plan est vide.
# Lecture seule.

# shellcheck source=_m05-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-expert.sh"

title "M05-E40 — État et réalité réconciliés (envs/lab-m05)"
require_cmd tofu jq

# Ensemble des VMID env-m05 de Proxmox = ensemble des VMID de l'état envs.
# Les VMs env-m05 du module appartiennent à envs/lab-m05 ou à envs/recette-m05 (M05-E15, E17) :
# on compare Proxmox à l'union des deux états (recette-m05 seulement si le dossier existe).
_m05_e40_recette="$_m05x_infra/envs/recette-m05"
_m05_e40_memes_vms() {
  local pve etat
  _m05x_show_calc "$_m05x_envs"
  etat="$(_m05x_vmids "$_m05x_envs")"
  [[ -n "$etat" ]] || return 1
  if [[ -d "$_m05_e40_recette" ]]; then
    _m05x_show_calc "$_m05_e40_recette"
    etat="$(printf '%s\n%s\n' "$etat" "$(_m05x_vmids "$_m05_e40_recette")" | sed '/^$/d' | sort -n)"
  fi
  pve="$(_m05x_vms_env_pve | awk '{ print $1 }' | sort -n)"
  [[ "$pve" == "$etat" ]]
}

check_cmd "envs/lab-m05 : l'état est lisible" _m05x_tofu "$_m05x_envs" state list
check_cmd "VMs étiquetées env-m05 (Proxmox) = VMs des états envs/lab-m05 et envs/recette-m05" _m05_e40_memes_vms
check_cmd "envs/lab-m05 : « tofu plan » ne propose aucun changement" _m05x_plan_vide "$_m05x_envs"
check_cmd "envs/lab-m05 : aucune ressource marquée « tainted »" _m05x_aucune_ressource_tainted "$_m05x_envs"
check_cmd "panne M05-E40 close (lab/bin/break 05 40 --annuler après réparation)" _m05x_aucune_panne_active E40
