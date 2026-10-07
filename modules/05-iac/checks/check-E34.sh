# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E34.sh — M05-E34 « Un environnement complet en temps limité » (preprod-agenda)
# À lancer AVANT de détruire l'environnement. Code sur main, états chiffrés, VMs 2057-2059 en
# service avec les étiquettes, ressources et disque demandés. Le temps (T4 − T0) et la grille du
# corrigé relèvent de l'auto-évaluation.

# shellcheck source=_m05-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-production.sh"

title "M05-E34 — Préproduction de MédiAgenda"
require_cmd jq aws curl ssh
_m05p_charger

_m05_e34_env=terragrunt/live/preprod-agenda

title "Code (branche main)"
check_cmd "env.hcl : environnement preprod-agenda, VMID 2057, 2058, 2059" \
  _m05p_main_contient "$_m05_e34_env/env.hcl" 'preprod-agenda' '2057' '2058' '2059'
# _m05_e34_unites — unités acces et vms présentes, avec lock, et identiques à celles de dev-agenda.
_m05_e34_unites() {
  local u a b
  for u in acces vms; do
    _m05p_fichier_main "$_m05_e34_env/$u/.terraform.lock.hcl" || return 1
    a="$(_m05p_contenu_main "$_m05_e34_env/$u/terragrunt.hcl")"
    b="$(_m05p_contenu_main "terragrunt/live/dev-agenda/$u/terragrunt.hcl")"
    [[ -n "$a" && "$a" == "$b" ]] || return 1
  done
}
check_cmd "unités acces et vms : locks versionnés, terragrunt.hcl identiques aux autres environnements" _m05_e34_unites

title "États (tofu-state)"
for _m05_e34_u in acces vms; do
  check_cmd "envs/preprod-agenda/$_m05_e34_u : état présent et chiffré" \
    _m05p_objet_chiffre "envs/preprod-agenda/$_m05_e34_u/terraform.tfstate"
done

title "VMs (pve01)"
check_cmd "m05-pp-api1 (2057) : en service, étiquettes env-m05, preprod-agenda, app-api" \
  _m05p_vm_etiquettes 2057 env-m05 preprod-agenda app-api
check_cmd "m05-pp-api2 (2058) : en service, étiquettes env-m05, preprod-agenda, app-api" \
  _m05p_vm_etiquettes 2058 env-m05 preprod-agenda app-api
check_cmd "m05-pp-bdd (2059) : en service, étiquettes env-m05, preprod-agenda, app-bdd" \
  _m05p_vm_etiquettes 2059 env-m05 preprod-agenda app-bdd
check_cmd "m05-pp-bdd : 2 vCPU et 2 Go" _m05p_vm_filtre 2059 '.maxcpu == 2 and .maxmem == 2147483648'
check_cmd "m05-pp-api1 : 1 vCPU et 1 Go" _m05p_vm_filtre 2057 '.maxcpu == 1 and .maxmem == 1073741824'
check_cmd "m05-pp-bdd : disque de données de 10 Go sur local-nvme" \
  _m05p_vm_conf 2059 "^scsi[1-9]: ${WB_STORAGE_NVME:-local-nvme}:[^,]+,.*size=10G"

# _m05_e34_frontaux_sans_donnees — 2057 et 2058 existent et n'ont que leur disque système.
_m05_e34_frontaux_sans_donnees() {
  local id
  for id in 2057 2058; do
    _m05p_vm_conf "$id" '^name:' || return 1
    if _m05p_vm_conf "$id" '^scsi[1-9]:'; then return 1; fi
  done
}
check_cmd "les frontaux n'ont pas de disque de données" _m05_e34_frontaux_sans_donnees

# _m05_e34_pas_onboot — aucune des trois VMs ne démarre avec pve01.
_m05_e34_pas_onboot() {
  local id
  for id in 2057 2058 2059; do
    _m05p_vm_conf "$id" '^name:' || return 1
    if _m05p_vm_conf "$id" '^onboot: 1'; then return 1; fi
  done
}
check_cmd "pas de démarrage automatique (VMs d'environnement)" _m05_e34_pas_onboot
