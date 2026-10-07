# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c
#
# check-E16.sh — M05-E16 : Importer le socle existant sans le recréer
# Lecture seule : état socle (tofu show -json), plans sans verrou (dont un plan -destroy, qui
# doit ÉCHOUER), Proxmox (root sur pve01), documentation.

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E16 — Importer le socle existant sans le recréer"
require_cmd jq tofu git

for _m05o_v in 1001:adm01 1002:dns01 1004:git01 1007:runner01; do
  check_cmd "état socle : ${_m05o_v#*:} (${_m05o_v%%:*}) importée" _m05o_a_vmid "$_m05o_socle" "${_m05o_v%%:*}"
done
check_cmd "état socle : s3-01 (1006) toujours là" _m05o_a_vmid "$_m05o_socle" 1006
check_cmd "gw01 (1000) reste HORS de l'état (décision documentée)" \
  bash -c '! awk "{print \$2}" <<<"$1" | grep -qx 1000' _ "$(_m05o_adresses "$_m05o_socle")"
check_cmd "socle : plan sans aucun changement après l'import" _m05o_plan_vide "$_m05o_socle"

# Un plan de destruction du socle doit être REFUSÉ par prevent_destroy (rien n'est appliqué).
_m05o_destruction_refusee() {
  local sortie
  if sortie="$(_m05o_tofu "$_m05o_socle" plan -destroy -lock=false -refresh=false -no-color -input=false 2>&1)"; then
    return 1
  fi
  grep -q "cannot be destroyed" <<<"$sortie"
}
check_cmd "socle : « tofu plan -destroy » refusé (prevent_destroy sur les VMs importées)" _m05o_destruction_refusee
check_cmd "code : aucun fichier de configuration générée commité (-generate-config-out)" \
  bash -c '[ -z "$(git -C "$1" ls-files socle | grep -E "gen(er|ér)" )" ]' _ "$_m05o_infra"
for _m05o_id in 1001 1002 1004 1007; do
  check_ssh "VM $_m05o_id : toujours démarrée (l'import ne l'a pas touchée)" "$WB_PVE_HOST" "qm status $_m05o_id | grep -q running"
done
check_cmd "décision sur gw01 documentée (ADR dans docs/socle/adr/)" \
  bash -c 'grep -lis "gw01" "$1"/docs/socle/adr/*.md | xargs -r grep -lis -E "opentofu|tofu|iac" | grep -q .' _ "$_m05o_depot"
