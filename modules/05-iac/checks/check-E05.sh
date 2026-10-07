# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E05.sh — M05-E05 : Plan, apply, destroy et fichier d'état
# À lancer depuis adm01. Lecture seule : plans exportés en JSON dans ~/m05/e05/, état local
# de envs/lab-m05 (jq), configuration de la VM 2050 lue en root sur pve01, « tofu plan »
# sans verrou ni enregistrement.

# shellcheck source=_m05-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-decouverte.sh"

title "M05-E05 — Plan, apply, destroy et fichier d'état"
require_cmd jq tofu

_m05_dossier="$HOME/m05/e05"
_m05_adr="proxmox_virtual_environment_vm.essai"

# --- Les plans enregistrés ---------------------------------------------------------------------------
check_cmd "plan-memoire.json est un plan exporté (tofu show -json)" \
  jq -e '.format_version and (.resource_changes | type == "array")' "$_m05_dossier/plan-memoire.json"
check_output "plan-memoire.json : modification SUR PLACE de la VM d'essai, mémoire 1024 → 2048 Mo" '^true$' \
  jq -r --arg a "$_m05_adr" 'any(.resource_changes[]?; .address == $a and .change.actions == ["update"]
      and .change.before.memory[0].dedicated == 1024 and .change.after.memory[0].dedicated == 2048)' \
  "$_m05_dossier/plan-memoire.json"
check_output "plan-remplacement.json : REMPLACEMENT de la VM d'essai (destruction et création)" '^true$' \
  jq -r --arg a "$_m05_adr" 'any(.resource_changes[]?; .address == $a
      and ((.change.actions | sort) == ["create", "delete"]))' "$_m05_dossier/plan-remplacement.json"
check_cmd "notes.md rédigé (au moins 15 lignes)" \
  bash -c '[ "$(grep -cv "^[[:space:]]*$" "$1" 2>/dev/null || echo 0)" -ge 15 ]' _ "$_m05_dossier/notes.md"

# --- L'état a vécu ---------------------------------------------------------------------------------------
if _m05_backend_distant; then
  skip "sauvegarde de l'état local et numéro de série" "état de envs/lab-m05 sur un backend distant"
else
  check_cmd "l'état local a une sauvegarde (terraform.tfstate.backup)" test -s "$_M05_ENV/terraform.tfstate.backup"
  check_output "l'état local a été réécrit à chaque opération (serial ≥ 5)" '^ok$' \
    _m05_etat 'if (.serial // 0) >= 5 then "ok" else "non" end'
  check_cmd "même lignée pour l'état et sa sauvegarde (aucun état recréé de zéro)" \
    bash -c '[ "$(jq -r .lineage "$1/terraform.tfstate")" = "$(jq -r .lineage "$1/terraform.tfstate.backup")" ]' \
    _ "$_M05_ENV"
fi

# --- La VM à la fin de l'exercice ---------------------------------------------------------------------------
_m05_cfg="$(_m05_qm_config 2050)"
check_output "VM 2050 : 2048 Mo de mémoire" '^2048$' _m05_cle "$_m05_cfg" memory
check_cmd "VM 2050 : étiquette env-m05, sans étiquette héritée du template (gold, current…)" \
  _m05_etiquettes_saines 2050
# La valeur peut être dans main.tf (E05), dans terraform.tfvars ou en défaut de variable (E06+).
check_output "main : la mémoire de 2048 Mo est dans le code (pas seulement sur la VM)" '\b2048\b' _m05_tf_main
_m05_controles_etat_et_plan "l'état connaît la VM d'essai" \
  '[.resources[]? | select(.mode == "managed" and .type == "proxmox_virtual_environment_vm")
    | .instances[].attributes.vm_id] | index(2050) != null'
