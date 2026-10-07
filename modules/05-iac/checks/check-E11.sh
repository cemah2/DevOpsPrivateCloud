# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c ou l'hôte distant
#
# check-E11.sh — M05-E11 : Backend S3 et migration de l'état
# Lecture seule : copie de travail ~/src/infra, objets du compartiment (identité tofu-etat),
# tofu state list / plan sans verrou.

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E11 — Backend S3 et migration de l'état"
require_cmd jq aws tofu git

for _m05o_d in socle envs/lab-m05; do
  _m05o_dir="$_m05o_infra/$_m05o_d"
  check_cmd "$_m05o_d : backend « s3 » déclaré" _m05o_code "$_m05o_dir" 'backend[[:space:]]+"s3"'
  check_cmd "$_m05o_d : clé $_m05o_d/terraform.tfstate dans tofu-state" \
    _m05o_code "$_m05o_dir" "key[[:space:]]*=[[:space:]]*\"$_m05o_d/terraform\\.tfstate\""
  check_cmd "$_m05o_d : adresse de s3-01 en HTTPS sur 8333, chemins de style « path »" \
    bash -c 'grep -Eqs "https://s3-01\.par1\.medisphere\.internal:8333" "$1"/*.tf && grep -Eqs "use_path_style[[:space:]]*=[[:space:]]*true" "$1"/*.tf' _ "$_m05o_dir"
  check_cmd "$_m05o_d : aucun identifiant S3 dans le code" \
    bash -c '! grep -Eqs "^[[:space:]]*(access_key|secret_key)[[:space:]]*=" "$1"/*.tf' _ "$_m05o_dir"
  check_output "$_m05o_d : dossier de travail initialisé sur le backend s3" '^s3$' \
    jq -r '.backend.type // empty' "$_m05o_dir/.terraform/terraform.tfstate"
  check_cmd "$_m05o_d : plus d'état local (terraform.tfstate et sa sauvegarde supprimés)" \
    bash -c '! ls "$1"/terraform.tfstate "$1"/terraform.tfstate.backup >/dev/null 2>&1' _ "$_m05o_dir"
  check_cmd "$_m05o_d : l'état distant existe sur s3-01" _m05o_objet "$_m05o_d/terraform.tfstate"
done

check_cmd "état socle lu depuis s3-01 : la VM 1006 y est" _m05o_a_vmid "$_m05o_socle" 1006
check_cmd "état lab-m05 lu depuis s3-01 : au moins une VM 2050-2059" \
  bash -c 'awk "\$2 >= 2050 && \$2 <= 2059 { f = 1 } END { exit !f }" <<<"$1"' _ "$(_m05o_adresses "$_m05o_lab")"
check_cmd "socle : plan sans aucun changement (l'état migré décrit bien la réalité)" _m05o_plan_vide "$_m05o_socle"
check_cmd "Git : aucun fichier d'état suivi dans plateforme/infra" \
  bash -c '[ -z "$(git -C "$1" ls-files "*.tfstate" "*.tfstate.*")" ]' _ "$_m05o_infra"
check_cmd "Git : le backend est sur origin/main (MR fusionnée)" \
  bash -c 'git -C "$1" grep -q "use_lockfile" origin/main -- socle envs/lab-m05' _ "$_m05o_infra"
