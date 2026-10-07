# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c
#
# check-E17.sh — M05-E17 : Refactorer sans détruire, moved et removed
# Lecture seule : états socle, lab-m05, recette-m05 ; code ; Proxmox (root sur pve01).

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E17 — Refactorer sans détruire : moved et removed"
require_cmd jq tofu

# --- socle : s3-01 dans le module ---------------------------------------------------------------
check_cmd "état socle : s3-01 à l'adresse du module (module.s3_01…)" \
  _m05o_a_adresse "$_m05o_socle" '^module\.s3_01\.proxmox_virtual_environment_vm\.'
check_cmd "état socle : plus d'ancienne adresse proxmox_virtual_environment_vm.s3_01" \
  bash -c '! awk "{print \$1}" <<<"$1" | grep -qx "proxmox_virtual_environment_vm.s3_01"' _ "$(_m05o_adresses "$_m05o_socle")"
check_cmd "code socle : bloc moved conservé (ancienne adresse → module)" \
  bash -c 'grep -Ezqs "moved[[:space:]]*\{[^}]*from[[:space:]]*=[[:space:]]*proxmox_virtual_environment_vm\.s3_01" "$1"/*.tf' _ "$_m05o_socle"
check_cmd "s3-01 n'a pas été recréée : l'état socle garde son historique sur son disque de données" \
  bash -c '[ "$(jq -r "[.Versions[]? | select(.Key == \"socle/terraform.tfstate\")] | length" <<<"$1")" -ge 3 ]' _ \
  "$(_m05o_aws s3api list-object-versions --bucket "$_m05o_bucket" --prefix socle/terraform.tfstate 2>/dev/null)"
check_output "s3-01 : toujours protégée contre la suppression" '^protection: 1$' printf '%s\n' "$(_m05o_qm 1006)"

# --- lab-m05 : serveurs d'application dans le module, VM d'essai sortie sans destruction ---------
for _m05o_k in app01 app02 app03; do
  check_cmd "état lab-m05 : $_m05o_k à l'adresse du module" \
    _m05o_a_adresse "$_m05o_lab" "^module\\.app\\[\"$_m05o_k\"\\]\\.proxmox_virtual_environment_vm\\."
done
check_cmd "code lab-m05 : bloc removed avec destroy = false" \
  bash -c 'grep -Ezqs "removed[[:space:]]*\{.*destroy[[:space:]]*=[[:space:]]*false" "$1"/*.tf' _ "$_m05o_lab"
check_cmd "VM 2050 (m05-essai) toujours vivante" bash -c 'grep -q "^name: m05-essai$" <<<"$1"' _ "$(_m05o_qm 2050)"
check_cmd "VM 2050 : sortie de l'état de lab-m05" \
  bash -c '! awk "{print \$2}" <<<"$1" | grep -qx 2050' _ "$(_m05o_adresses "$_m05o_lab")"
check_cmd "VM 2050 : entrée dans l'état de recette-m05" _m05o_a_vmid "$_m05o_recette" 2050

for _m05o_d in "$_m05o_socle" "$_m05o_lab" "$_m05o_recette"; do
  check_cmd "${_m05o_d#"$_m05o_infra"/} : plan sans aucun changement" _m05o_plan_vide "$_m05o_d"
done
