# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E07.sh — M05-E07 : count, for_each et blocs dynamiques
# À lancer depuis adm01. Lecture seule : bac à sable ~/m05/e07/compteur (fichiers et état
# lus), VMs 2051-2053 lues en root sur pve01, code et état de envs/lab-m05, « tofu plan »
# sans verrou ni enregistrement.

# shellcheck source=_m05-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-decouverte.sh"

title "M05-E07 — count, for_each et blocs dynamiques"
require_cmd jq tofu

# --- Partie A : le bac à sable -----------------------------------------------------------------------
_m05_bac="$HOME/m05/e07/compteur"
check_cmd "bac à sable : terraform_data passé à for_each" \
  bash -c 'grep -Eqs "^[[:space:]]*for_each[[:space:]]*=" "$1"/*.tf && ! grep -Eqs "^[[:space:]]*count[[:space:]]*=" "$1"/*.tf' \
  _ "$_m05_bac"
check_output "bac à sable : les instances de l'état sont adressées par clé (app01…)" '^true$' \
  jq -r '[.resources[]? | select(.type == "terraform_data") | .instances[].index_key]
    | (length > 0) and all(type == "string")' "$_m05_bac/terraform.tfstate"
check_cmd "notes.md rédigé (au moins 15 lignes)" \
  bash -c '[ "$(grep -cv "^[[:space:]]*$" "$1" 2>/dev/null || echo 0)" -ge 15 ]' _ "$HOME/m05/e07/notes.md"

# --- Partie B : les serveurs de Julien dans Proxmox -----------------------------------------------------
# _m05_disque CONFIG INTERFACE — taille en Go du disque (vide s'il n'existe pas).
_m05_disque() { _m05_cle "$1" "$2" | grep -oE 'size=[0-9]+G' | grep -oE '[0-9]+' || true; }

for _m05_n in 1 2 3; do
  _m05_id="205$_m05_n"
  _m05_cfg="$(_m05_qm_config "$_m05_id")"
  check_output "VM $_m05_id : nom m05-app0$_m05_n" "^m05-app0$_m05_n\$" _m05_cle "$_m05_cfg" name
  check_output "VM $_m05_id : dans le pool lab, démarrée" '^lab running$' \
    _m05_val "$(_m05_ressource "$_m05_id")" '"\(.pool // "") \(.status // "")"'
  check_cmd "VM $_m05_id : étiquette env-m05, sans étiquette héritée ou réservée" _m05_etiquettes_saines "$_m05_id"
  check_output "VM $_m05_id : carte réseau sur vsandbox" 'bridge=vsandbox([,]|$)' _m05_cle "$_m05_cfg" net0
  case "$_m05_n" in
    1) check_cmd "VM 2051 : aucun disque de données (pas de scsi1)" \
         bash -c '[ -z "$1" ]' _ "$(_m05_disque "$_m05_cfg" scsi1)" ;;
    2) check_output "VM 2052 : disque de données scsi1 de 2 Go" '^2$' _m05_disque "$_m05_cfg" scsi1
       check_cmd "VM 2052 : pas de second disque de données (scsi2)" \
         bash -c '[ -z "$1" ]' _ "$(_m05_disque "$_m05_cfg" scsi2)" ;;
    3) check_output "VM 2053 : disque de données scsi1 de 2 Go" '^2$' _m05_disque "$_m05_cfg" scsi1
       check_output "VM 2053 : disque de données scsi2 de 3 Go" '^3$' _m05_disque "$_m05_cfg" scsi2 ;;
  esac
done
check_output "la VM d'essai 2050 n'a pas été touchée (toujours m05-essai)" '^m05-essai$' \
  _m05_cle "$(_m05_qm_config 2050)" name

# --- Le code -----------------------------------------------------------------------------------------------
_m05_conf="$(_m05_config_json)"
check_output "variable vms_app : dictionnaire d'objets" '^map$' \
  _m05_val "$_m05_conf" '.root_module.variables.vms_app.type[0] // empty'
check_output "ressource proxmox_virtual_environment_vm.app répétée par for_each (et non count)" '^true$' \
  _m05_val "$_m05_conf" '[.root_module.resources[] | select(.address == "proxmox_virtual_environment_vm.app")][0]
    | (.for_each_expression != null) and (.count_expression == null)'
check_cmd "disques de données produits par un bloc dynamic \"disk\"" \
  _m05_tf_contient '^[[:space:]]*dynamic[[:space:]]+"disk"[[:space:]]*\{'
check_output "main : envs/lab-m05 déclare la ressource app" \
  'resource[[:space:]]+"proxmox_virtual_environment_vm"[[:space:]]+"app"' _m05_tf_main

# --- État et plan ----------------------------------------------------------------------------------------------
_m05_controles_etat_et_plan "l'état adresse les serveurs par clé : app[\"app01\"], app[\"app02\"], app[\"app03\"]" \
  '[.resources[]? | select(.mode == "managed" and .name == "app") | .instances[].index_key] | sort
    == ["app01", "app02", "app03"]'
