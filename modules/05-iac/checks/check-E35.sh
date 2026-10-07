# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E35.sh — M05-E35 « Panne : le plan veut recréer une VM du socle » : le plan du socle est
# vide, chaque VM permanente est dans l'état à une adresse décrite par le code, une seule image
# dorée Debian porte « current », aucun fichier de surcharge ne traîne. Lecture seule (plan sans
# verrou).

# shellcheck source=_m05-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-expert.sh"

title "M05-E35 — Le plan du socle ne recrée aucune VM"
require_cmd tofu jq

_m05_e35_prevent() {
  grep -rEqs 'prevent_destroy[[:space:]]*=[[:space:]]*true' --include='*.tf' "$_m05x_socle"
}

check_cmd "socle : « tofu plan » ne propose aucun changement" _m05x_plan_vide "$_m05x_socle"
check_cmd "socle : adm01, dns01, git01, s3-01 et runner01 (1001, 1002, 1004, 1006, 1007) sont dans l'état" \
  _m05x_etat_contient "$_m05x_socle" 1001 1002 1004 1006 1007
check_cmd "socle : les VMs permanentes sont protégées par prevent_destroy dans le code" _m05_e35_prevent
check_output "pve01 : une et une seule image dorée Debian porte l'étiquette current" '^1$' _m05x_nb_current
check_cmd "infra : aucun fichier de surcharge (*_override.tf) dans la copie de travail" _m05x_aucun_override
check_output "infra : copie de travail sans modification non commitée" '^$' git -C "$_m05x_infra" status --porcelain
check_cmd "panne M05-E35 close (lab/bin/break 05 35 --annuler après réparation)" _m05x_aucune_panne_active E35
