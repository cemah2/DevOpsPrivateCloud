# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E41.sh — M05-E41 « Panne : le plan est cassé du jour au lendemain » : les plans socle et
# envs aboutissent sans changement, les fichiers de verrouillage des providers sont ceux du dépôt
# et couvrent plusieurs plateformes, l'image current est unique, l'état se déchiffre, le dernier
# pipeline de main est vert. Lecture seule.

# shellcheck source=_m05-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-expert.sh"

title "M05-E41 — Plans de nouveau fonctionnels"
require_cmd tofu jq git curl

# Le lock de bpg/proxmox contient des empreintes zh: (registre, toutes plateformes) en plus des h1:.
_m05_e41_lock_complet() {
  awk '/provider ".*bpg\/proxmox"/ { p = 1 } p && /"zh:/ { z++ } p && /^}/ { p = 0 } END { exit !(z > 0) }' "$1/.terraform.lock.hcl" 2>/dev/null
}
_m05_e41_pipeline() {
  gitlab_api "projects/plateforme%2Finfra/pipelines?ref=main&per_page=1" | jq -e '.[0].status == "success"' >/dev/null
}

check_cmd "socle : « tofu plan » aboutit sans changement" _m05x_plan_vide "$_m05x_socle"
check_cmd "envs/lab-m05 : « tofu plan » aboutit sans changement" _m05x_plan_vide "$_m05x_envs"
check_cmd "socle : .terraform.lock.hcl versionné et identique au dépôt" _m05x_lock_suivi "$_m05x_socle"
check_cmd "envs/lab-m05 : .terraform.lock.hcl versionné et identique au dépôt" _m05x_lock_suivi "$_m05x_envs"
check_cmd "socle : le lock de bpg/proxmox contient les empreintes zh: du registre" _m05_e41_lock_complet "$_m05x_socle"
check_cmd "socle : les providers installés sont cohérents avec le lock (tofu validate)" _m05x_tofu "$_m05x_socle" validate -no-color
check_output "pve01 : une et une seule image dorée Debian porte l'étiquette current" '^1$' _m05x_nb_current
check_cmd "envs/lab-m05 : l'état se déchiffre avec la phrase de adm01 (state list)" _m05x_tofu "$_m05x_envs" state list
check_cmd "forge : dernier pipeline de main de plateforme/infra réussi" _m05_e41_pipeline
check_cmd "panne M05-E41 close (lab/bin/break 05 41 --annuler après réparation)" _m05x_aucune_panne_active E41
