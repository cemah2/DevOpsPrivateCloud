# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c
#
# check-E15.sh — M05-E15 : Environnements, workspaces ou répertoires ?
# Lecture seule : copie de travail, versions du compartiment, Proxmox (root sur pve01).

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E15 — Environnements : workspaces ou répertoires ?"
require_cmd jq aws tofu

# --- L'essai des espaces de travail a eu lieu, et il est nettoyé ----------------------------------
_m05o_espaces() {
  _m05o_aws s3api list-object-versions --bucket "$_m05o_bucket" --prefix "env:/" \
    | jq -r '[.Versions[]?, .DeleteMarkers[]?] | length'
}
_m05o_espaces_vivants() {
  _m05o_aws s3api list-objects-v2 --bucket "$_m05o_bucket" --prefix "env:/" | jq -r '.KeyCount // 0'
}
check_output "essai des workspaces : des états env:/<espace>/… ont existé sur s3-01" '^[1-9][0-9]*$' _m05o_espaces
check_output "essai terminé : plus aucun état de workspace en cours (espaces supprimés)" '^0$' _m05o_espaces_vivants

# --- La recette, en répertoire -----------------------------------------------------------------
check_cmd "envs/recette-m05 : backend s3, clé envs/recette-m05/terraform.tfstate" \
  _m05o_code "$_m05o_recette" 'key[[:space:]]*=[[:space:]]*"envs/recette-m05/terraform\.tfstate"'
check_cmd "envs/recette-m05 : verrou natif" _m05o_code "$_m05o_recette" 'use_lockfile[[:space:]]*=[[:space:]]*true'
check_cmd "envs/recette-m05 : VMs créées par le module versionné (?ref=vX.Y.Z)" \
  _m05o_code "$_m05o_recette" 'tofu-modules\.git//vm-debian\?ref=v[0-9]+\.[0-9]+\.[0-9]+"'
check_cmd "envs/recette-m05 : aucun terraform.workspace dans le code" \
  bash -c '! grep -qs "terraform.workspace" "$1"/*.tf' _ "$_m05o_recette"
check_cmd "état recette-m05 sur s3-01" _m05o_objet envs/recette-m05/terraform.tfstate
for _m05o_v in 2055:m05-rec-api 2056:m05-rec-bdd; do
  _m05o_c="$(_m05o_qm "${_m05o_v%%:*}")"
  check_output "VM ${_m05o_v%%:*} : ${_m05o_v#*:}, étiquetée env-m05" "^name: ${_m05o_v#*:}$" printf '%s\n' "$_m05o_c"
  check_cmd "VM ${_m05o_v%%:*} : dans l'état de recette-m05" _m05o_a_vmid "$_m05o_recette" "${_m05o_v%%:*}"
  check_cmd "VM ${_m05o_v%%:*} : PAS dans l'état de lab-m05 (un objet, un seul état)" \
    bash -c '! awk "{print \$2}" <<<"$1" | grep -qx "$2"' _ "$(_m05o_adresses "$_m05o_lab")" "${_m05o_v%%:*}"
done
check_cmd "recette-m05 : plan sans aucun changement" _m05o_plan_vide "$_m05o_recette"
check_cmd "lab-m05 : plan sans aucun changement (la recette ne l'a pas touché)" _m05o_plan_vide "$_m05o_lab"
check_cmd "décision documentée (docs/environnements.md de plateforme/infra)" \
  bash -c 'grep -qi "workspace" "$1" && grep -qi "répertoire" "$1"' _ "$_m05o_infra/docs/environnements.md"
