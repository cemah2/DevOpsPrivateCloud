# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E38.sh — M05-E38 « Panne : l'apply échoue sur un refus de droits » : le jeton wb-tofu a
# exactement les privilèges qu'exige le cycle de vie d'une VM d'environnement (et pas de droits
# d'administration), l'environnement est appliqué, aucune ressource n'est « tainted ». Lecture seule.

# shellcheck source=_m05-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-expert.sh"

title "M05-E38 — Droits du jeton wb-tofu et environnement appliqué"
require_cmd tofu jq

_m05_e38_perms() { remote "$WB_PVE_HOST" "pveum user token permissions wb-tofu@pve tofu --path $1" 2>/dev/null; }

# _m05_e38_a CHEMIN PRIV… — le jeton a tous ces privilèges sur CHEMIN.
_m05_e38_a() {
  local p out
  out="$(_m05_e38_perms "$1")" || return 1
  shift
  for p in "$@"; do grep -qw -- "$p" <<<"$out" || return 1; done
}
# _m05_e38_na_pas CHEMIN PRIV… — le jeton n'a aucun de ces privilèges sur CHEMIN.
_m05_e38_na_pas() {
  local p out
  out="$(_m05_e38_perms "$1")" || return 1
  shift
  for p in "$@"; do grep -qw -- "$p" <<<"$out" && return 1; done
  return 0
}
_m05_e38_vm_env() { _m05x_vmids "$_m05x_envs" | awk '$1 >= 2050 && $1 <= 2059 { f = 1 } END { exit !f }'; }

_m05_e38_sto="${WB_STORAGE_NVME:-local-nvme}"
check_cmd "jeton : cycle de vie des VMs sur /pool/lab (VM.Allocate, VM.Clone, VM.Config.Memory, VM.PowerMgmt)" \
  _m05_e38_a /pool/lab VM.Allocate VM.Clone VM.Config.Memory VM.PowerMgmt
check_cmd "jeton : SDN.Use sur le VNet vsandbox" _m05_e38_a /sdn/zones/lab/vsandbox SDN.Use
check_cmd "jeton : Datastore.AllocateSpace sur $_m05_e38_sto" _m05_e38_a "/storage/$_m05_e38_sto" Datastore.AllocateSpace
check_cmd "jeton : aucun droit d'administration sur / (Permissions.Modify, Sys.Modify, User.Modify, Realm.Allocate)" \
  _m05_e38_na_pas / Permissions.Modify Sys.Modify User.Modify Realm.Allocate
check_cmd "envs/lab-m05 : au moins une VM d'environnement (2050-2059) dans l'état" _m05_e38_vm_env
check_cmd "envs/lab-m05 : aucune ressource marquée « tainted »" _m05x_aucune_ressource_tainted "$_m05x_envs"
check_cmd "envs/lab-m05 : « tofu plan » ne propose aucun changement" _m05x_plan_vide "$_m05x_envs"
check_cmd "panne M05-E38 close (lab/bin/break 05 38 --annuler après réparation)" _m05x_aucune_panne_active E38
