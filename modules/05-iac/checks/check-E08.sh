# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E08.sh — M05-E08 : Sources de données : trouver l'image dorée courante
# À lancer depuis adm01. Lecture seule : configuration lue par « tofu show -json -config »
# et dans les fichiers .tf, image courante lue en root sur pve01 (pvesh), état local (jq),
# « tofu plan » sans verrou ni enregistrement.

# shellcheck source=_m05-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-decouverte.sh"

title "M05-E08 — Sources de données : trouver l'image dorée courante"
require_cmd jq tofu

# --- L'image courante, vue de pve01 -----------------------------------------------------------------
_m05_tout="$(_m05_pve "pvesh get /cluster/resources --type vm --output-format json")"
_m05_courantes="$(jq -r '[.[] | select(.template == 1)
    | select((.tags // "") | split(";") | (index("gold") and index("debian13") and index("current")))
    | .vmid] | map(tostring) | join(" ")' <<<"$_m05_tout" 2>/dev/null || true)"
check_output "Proxmox : exactement un template gold + debian13 + current (prérequis M03)" '^[0-9]+$' \
  printf '%s\n' "$_m05_courantes"

# --- La source de données -----------------------------------------------------------------------------
_m05_conf="$(_m05_config_json)"
_m05_ds='[.root_module.resources[] | select(.mode == "data" and .type == "proxmox_virtual_environment_vms")]'
check_output "source de données proxmox_virtual_environment_vms déclarée" '^[1-9]' \
  _m05_val "$_m05_conf" "$_m05_ds | length"
check_output "elle exige les étiquettes gold, debian13 et current" '^true$' \
  _m05_val "$_m05_conf" "$_m05_ds | any(.expressions.tags.constant_value // [] | (index(\"gold\") and index(\"debian13\") and index(\"current\")))"
check_output "elle ne retient que les templates (filtre template)" '^true$' \
  _m05_val "$_m05_conf" "$_m05_ds | any(.expressions.filter // [] | any(.name.constant_value == \"template\"))"
check_cmd "une postcondition protège la lecture (lifecycle { postcondition })" \
  _m05_tf_contient '^[[:space:]]*postcondition[[:space:]]*\{'
check_cmd "la source dépréciée proxmox_virtual_environment_vm (une seule VM) n'est pas utilisée" \
  bash -c '! grep -Eqs "^[[:space:]]*data[[:space:]]+\"proxmox_virtual_environment_vm\"" "$1"/*.tf' _ "$_M05_ENV"
check_cmd "plus aucun VMID de template écrit en dur (90xx) dans le code ni dans terraform.tfvars" \
  bash -c '! grep -Eqs "^[^#]*(vm_id|image_vmid)[[:space:]]*=[[:space:]]*90[0-9]{2}\b" "$1"/*.tf "$1"/*.tfvars' _ "$_M05_ENV"
check_output "la variable image_vmid a disparu" '^false$' \
  _m05_val "$_m05_conf" '.root_module.variables | has("image_vmid")'
# ignore_changes est une méta-donnée de lifecycle, absente de « show -config » : lue dans les fichiers.
# _m05_ignore_clone — nombre de listes ignore_changes (sur une ou plusieurs lignes) contenant clone.
_m05_ignore_clone() {
  cat "$_M05_ENV"/*.tf 2>/dev/null | awk '
    /^[[:space:]]*ignore_changes[[:space:]]*=/ { c = 1; buf = "" }
    c { buf = buf " " $0; if ($0 ~ /\]/) { if (buf ~ /[^a-z_]clone[^a-z_]/) n++; c = 0 } }
    END { print n + 0 }'
}
check_output "les ressources de VM (essai et app) ignorent les changements de leur bloc clone" '^([2-9]|[1-9][0-9])$' _m05_ignore_clone
check_cmd "un bloc check surveille la place libre (proxmox_datastores)" \
  bash -c 'grep -Eqs "^[[:space:]]*check[[:space:]]+\"" "$1"/*.tf && grep -Eqs "\"proxmox_datastores\"" "$1"/*.tf' _ "$_M05_ENV"
check_output "main : la source de données est sur main" 'data[[:space:]]+"proxmox_virtual_environment_vms"' _m05_tf_main

# --- Sortie, état et plan ----------------------------------------------------------------------------------
if _m05_backend_distant; then
  skip "sortie image_source" "état de envs/lab-m05 sur un backend distant : voir lab/bin/check 05 11"
else
  check_output "sortie image_source : le template courant vu par Proxmox ($_m05_courantes)" "^${_m05_courantes:-aucun}\$" \
    _m05_etat '.outputs.image_source.value.vmid // empty'
fi
_m05_controles_etat_et_plan "l'état connaît la source de données de l'image courante" \
  '[.resources[]? | select(.mode == "data" and .type == "proxmox_virtual_environment_vms")] | length > 0'
