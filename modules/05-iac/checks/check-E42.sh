# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E42.sh — M05-E42 « Panne : l'état a disparu » : le compartiment est versionné, l'objet
# courant de l'état socle est une vraie version (historique conservé), la configuration pointe sur
# la bonne clé et l'espace default, l'état contient le socle et le plan est vide. Lecture seule.

# shellcheck source=_m05-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-expert.sh"

title "M05-E42 — État du socle retrouvé"
require_cmd tofu aws jq

_m05_e42_courant() { [[ "$(_m05x_s3_dernier "$_m05x_cle_socle")" == version:* ]]; }
_m05_e42_historique() { [[ "$(_m05x_s3_nb_versions "$_m05x_cle_socle")" -ge 2 ]]; }
_m05_e42_cle_code() {
  grep -rEqs 'key[[:space:]]*=[[:space:]]*"socle/terraform\.tfstate"' "$_m05x_socle"/*.tf "$_m05x_socle"/*.hcl "$_m05x_socle"/*.tfbackend
}
_m05_e42_cle_init() {
  jq -e '.backend.config.key == "socle/terraform.tfstate"' "$_m05x_socle/.terraform/terraform.tfstate" >/dev/null 2>&1
}
_m05_e42_espace() {
  [[ ! -f "$_m05x_socle/.terraform/environment" || "$(cat "$_m05x_socle/.terraform/environment")" == default ]]
}

check_cmd "S3 : versionnage actif sur tofu-state" _m05x_versionnage_actif
check_cmd "S3 : l'objet courant de socle/terraform.tfstate est une version (pas un marqueur de suppression)" _m05_e42_courant
check_cmd "S3 : l'historique de l'état socle est conservé (au moins 2 versions)" _m05_e42_historique
check_cmd "socle : le code déclare la clé socle/terraform.tfstate" _m05_e42_cle_code
check_cmd "socle : la configuration initialisée utilise cette clé (.terraform/terraform.tfstate)" _m05_e42_cle_init
check_cmd "socle : espace de travail default sélectionné" _m05_e42_espace
check_cmd "socle : l'état contient adm01, dns01, git01, s3-01 et runner01" \
  _m05x_etat_contient "$_m05x_socle" 1001 1002 1004 1006 1007
check_cmd "socle : « tofu plan » ne propose aucun changement" _m05x_plan_vide "$_m05x_socle"
check_cmd "panne M05-E42 close (lab/bin/break 05 42 --annuler après réparation)" _m05x_aucune_panne_active E42
