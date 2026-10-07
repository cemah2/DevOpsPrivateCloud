# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c ou l'hôte distant
#
# check-E12.sh — M05-E12 : Verrouiller l'état partagé
# Lecture seule : code, objets et versions du compartiment (identité tofu-etat).

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E12 — Verrouiller l'état partagé"
require_cmd jq aws git

for _m05o_d in socle envs/lab-m05; do
  _m05o_dir="$_m05o_infra/$_m05o_d"
  check_cmd "$_m05o_d : verrou natif activé (use_lockfile = true)" \
    _m05o_code "$_m05o_dir" 'use_lockfile[[:space:]]*=[[:space:]]*true'
  check_cmd "$_m05o_d : aucun verrou DynamoDB" \
    bash -c '! grep -Eqs "dynamodb_(table|endpoint)" "$1"/*.tf' _ "$_m05o_dir"
  check_cmd "$_m05o_d : aucun verrou en cours ni oublié ($_m05o_d/terraform.tfstate.tflock absent)" \
    _m05o_pas_objet "$_m05o_d/terraform.tfstate.tflock"
done

# Les versions d'un .tflock prouvent que le verrou a réellement été pris (et rendu).
_m05o_versions_verrou() {
  _m05o_aws s3api list-object-versions --bucket "$_m05o_bucket" --prefix "$1" \
    | jq '[.Versions[]?, .DeleteMarkers[]? | select(.Key | endswith(".tflock"))] | length'
}
check_output "historique : le verrou de envs/lab-m05 a été pris et rendu" '^[1-9][0-9]*$' \
  _m05o_versions_verrou envs/lab-m05/
check_cmd "outils/s3-tester-ecriture-conditionnelle.sh présent et exécutable" \
  test -x "$_m05o_infra/outils/s3-tester-ecriture-conditionnelle.sh"
check_output "le test d'écriture conditionnelle a été lancé sur tofu-state (objets _essais/)" '^[1-9][0-9]*$' \
  _m05o_aws s3api list-object-versions --bucket "$_m05o_bucket" --prefix _essais/ --query 'length(Versions)'
