# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E31.sh — M05-E31 « Mettre à jour les providers sans surprise »
# Contraintes ~> 0.116.0 et locks 0.116.x sur main pour chaque configuration racine et pour le
# composant Terragrunt vms, plans vides avec le nouveau provider, apply du socle par le pipeline
# après la fusion, procédure écrite dans docs/socle/iac.md.

# shellcheck source=_m05-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-production.sh"

title "M05-E31 — Montée de version du provider bpg/proxmox"
require_cmd jq curl tofu

# _m05_e31_lock FICHIER — le lock sur main fixe bpg/proxmox en 0.116.x.
_m05_e31_lock() {
  _m05p_contenu_main "$1" | awk '/provider "registry.opentofu.org\/bpg\/proxmox"/ {p=1} p && /version/ {print; exit}' \
    | grep -Eq '"0\.116\.[0-9]+"'
}

# _m05_e31_deploiement_recent — le dernier déploiement réussi de lab/socle est postérieur au
#   dernier commit de main qui a modifié socle/.terraform.lock.hcl.
_m05_e31_deploiement_recent() {
  local d c
  d="$(gitlab_api "$_M05P_PROJET/deployments?environment=lab%2Fsocle&status=success&order_by=created_at&sort=desc&per_page=1" 2>/dev/null \
    | jq -r '.[0].created_at // empty')" || return 1
  c="$(gitlab_api "$_M05P_PROJET/repository/commits?ref_name=main&path=socle%2F.terraform.lock.hcl&per_page=1" 2>/dev/null \
    | jq -r '.[0].committed_date // empty')" || return 1
  [[ -n "$d" && -n "$c" ]] || return 1
  # date (GNU) lit l'ISO 8601 avec millisecondes et décalage horaire.
  [[ "$(date -d "$d" +%s 2>/dev/null || echo 0)" -ge "$(date -d "$c" +%s 2>/dev/null || echo 9999999999)" ]]
}

title "Contraintes et locks (branche main)"
for _m05_e31_c in socle envs/lab-m05 envs/recette-m05 terragrunt/composants/vms; do
  check_cmd "$_m05_e31_c : contrainte bpg/proxmox ~> 0.116.0" \
    _m05p_main_contient "$_m05_e31_c/versions.tf" 'version[[:space:]]*=[[:space:]]*"~>[[:space:]]*0\.116\.0"'
done
for _m05_e31_c in socle envs/lab-m05 envs/recette-m05; do
  check_cmd "$_m05_e31_c/.terraform.lock.hcl : bpg/proxmox 0.116.x" _m05_e31_lock "$_m05_e31_c/.terraform.lock.hcl"
done

title "Plans avec le nouveau provider (copie locale)"
for _m05_e31_c in socle envs/lab-m05 envs/recette-m05; do
  check_cmd "$_m05_e31_c : « tofu plan » ne propose aucun changement" _m05p_plan_vide "$_M05P_INFRA/$_m05_e31_c"
done

title "Application et procédure"
check_cmd "lab/socle : déploiement réussi après la mise à jour du lock" _m05_e31_deploiement_recent
check_cmd "docs/socle/iac.md : procédure de montée de version (journal, locks, plans, retour arrière)" \
  _m05p_doc_contient "$_M05P_DOC/iac.md" 'providers? lock' 'CHANGELOG|journal des modifications' 'retour arrière'
