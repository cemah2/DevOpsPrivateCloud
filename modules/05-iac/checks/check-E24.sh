# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E24.sh — M05-E24 « Terragrunt : factoriser backends, providers et environnements »
# Terragrunt 1.x sur adm01, arborescence live/ et composants sur main, clés d'état déduites du
# chemin dans tofu-state, VMs 2057-2059 créées (puis 2059 détruite) par l'exercice.
# Après M05-E27 (destruction de dev-agenda), les VMs 2057-2058 ne tournent plus : le contrôle se
# fonde sur l'historique des tâches de Proxmox, pas sur leur présence.

# shellcheck source=_m05-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-production.sh"

title "M05-E24 — Terragrunt"
require_cmd jq aws curl ssh

_m05_e24_live="terragrunt/live"

title "Outil"
check_output "terragrunt 1.x installé sur adm01" '^terragrunt version v1\.' terragrunt --version

title "Code (branche main de plateforme/infra)"
check_cmd "$_m05_e24_live/root.hcl : backend S3 généré, clé déduite du chemin" \
  _m05p_main_contient "$_m05_e24_live/root.hcl" '^remote_state' 'path_relative_to_include\(\)' 'use_lockfile[[:space:]]*=[[:space:]]*true' 'generate'
_m05_e24_pas_de_racine() { ! _m05p_fichier_main "$_m05_e24_live/terragrunt.hcl"; }
check_cmd "aucun terragrunt.hcl directement dans live/ (Terragrunt 1.x : root.hcl)" _m05_e24_pas_de_racine

# _m05_e24_unite DOSSIER — terragrunt.hcl et .terraform.lock.hcl de l'unité sont sur main.
_m05_e24_unite() { _m05p_fichier_main "$1/terragrunt.hcl" && _m05p_fichier_main "$1/.terraform.lock.hcl"; }
for _m05_e24_env in dev-agenda dev-doc; do
  check_cmd "$_m05_e24_env : env.hcl présent" _m05p_fichier_main "$_m05_e24_live/$_m05_e24_env/env.hcl"
  for _m05_e24_u in acces vms; do
    check_cmd "$_m05_e24_env/$_m05_e24_u : terragrunt.hcl et .terraform.lock.hcl versionnés" \
      _m05_e24_unite "$_m05_e24_live/$_m05_e24_env/$_m05_e24_u"
  done
done
check_cmd "unité vms : dépendance vers acces, sorties factices limitées à validate/plan" \
  _m05p_main_contient "$_m05_e24_live/dev-agenda/vms/terragrunt.hcl" 'dependency[[:space:]]+"acces"' 'mock_outputs_allowed_terraform_commands'

# _m05_e24_identiques UNITÉ — le terragrunt.hcl de l'unité est le même dans les deux environnements.
_m05_e24_identiques() {
  local a b
  a="$(_m05p_contenu_main "$_m05_e24_live/dev-agenda/$1/terragrunt.hcl")"
  b="$(_m05p_contenu_main "$_m05_e24_live/dev-doc/$1/terragrunt.hcl")"
  [[ -n "$a" && "$a" == "$b" ]]
}
check_cmd "unité acces : terragrunt.hcl identique dans dev-agenda et dev-doc" _m05_e24_identiques acces
check_cmd "unité vms : terragrunt.hcl identique dans dev-agenda et dev-doc" _m05_e24_identiques vms
_m05_e24_composants_purs() {
  local d="$_M05P_INFRA/terragrunt/composants"
  [[ -d "$d" ]] || return 1
  ! grep -rEqs --include='*.tf' '^[[:space:]]*(backend[[:space:]]+"|provider[[:space:]]+")' "$d"
}
check_cmd "composants (copie locale) : aucun bloc backend ni provider" _m05_e24_composants_purs
check_output ".terragrunt-cache/ ignoré par Git" '\.terragrunt-cache' _m05p_contenu_main .gitignore

title "États (tofu-state sur s3-01)"
for _m05_e24_cle in envs/dev-agenda/acces envs/dev-agenda/vms envs/dev-doc/acces envs/dev-doc/vms; do
  check_cmd "clé $_m05_e24_cle/terraform.tfstate présente" _m05p_cle_existe "$_m05_e24_cle/terraform.tfstate"
done

title "VMs (historique des tâches de pve01)"
# Une tâche « qmclone » est enregistrée sous le VMID de la SOURCE (le template), pas sous celui de la
# VM créée (fork_worker('qmclone', $vmid…) dans PVE/API2/Qemu.pm) : on cherche donc le premier
# démarrage (qmstart), enregistré sous le VMID de la VM elle-même.
for _m05_e24_id in 2057 2058 2059; do
  check_cmd "VM $_m05_e24_id : créée et démarrée (tâche qmstart réussie)" _m05p_tache_pve qmstart "$_m05_e24_id"
done
check_cmd "VM 2059 (dev-doc) : destruction réussie" _m05p_tache_pve qmdestroy 2059
