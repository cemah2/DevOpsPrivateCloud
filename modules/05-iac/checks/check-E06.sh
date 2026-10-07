# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1…)
#
# check-E06.sh — M05-E06 : Variables, locals, sorties, types et validations
# À lancer depuis adm01. Lecture seule : configuration lue par « tofu show -json -config »,
# garde-fous éprouvés par des « tofu plan -refresh=false » avec des valeurs INVALIDES (ils
# doivent être refusés avant tout appel de création ; aucun plan n'est enregistré ni
# appliqué), état local lu par jq, plan final sans verrou. Durée : 2 à 4 min.

# shellcheck source=_m05-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-decouverte.sh"

title "M05-E06 — Variables, locals, sorties, types et validations"
require_cmd jq tofu

# --- Les variables déclarées -------------------------------------------------------------------------
_m05_conf="$(_m05_config_json)"
check_cmd "tofu show -json -config lit la configuration de envs/lab-m05" test -n "$_m05_conf"
for _m05_v in noeud pool stockage_vm vnet environnement etiquettes_supplementaires cles_ssh_admin vm_essai; do
  check_output "variable $_m05_v déclarée, avec une description" '^true$' \
    _m05_val "$_m05_conf" ".root_module.variables.$_m05_v | (. != null) and ((.description // \"\") | length > 0)"
done
check_output "vm_essai : objet avec vmid et nom obligatoires, coeurs, memoire_mo et disque_go facultatifs" '^true$' \
  _m05_val "$_m05_conf" '.root_module.variables.vm_essai.type as $t
    | ($t[0] == "object") and ($t[1] | has("vmid") and has("nom") and has("coeurs") and has("memoire_mo") and has("disque_go"))
    and (($t[2] // []) | sort == ["coeurs", "disque_go", "memoire_mo"])'
check_output "cles_ssh_admin : liste de chaînes, obligatoire" '^true$' \
  _m05_val "$_m05_conf" '.root_module.variables.cles_ssh_admin | (.type == ["list", "string"]) and (.required == true)'
check_output "sortie essai déclarée" '^true$' _m05_val "$_m05_conf" '.root_module.outputs | has("essai")'
check_cmd "main contient envs/lab-m05/terraform.tfvars" _m05_fichier_main envs/lab-m05/terraform.tfvars
check_cmd "main contient envs/lab-m05/variables.tf" _m05_fichier_main envs/lab-m05/variables.tf
check_cmd "terraform.tfvars ne contient aucun secret (jeton, mot de passe, clé privée)" \
  bash -c '! grep -Eiq "PVEAPIToken|api_token[[:space:]]*=|password[[:space:]]*=|PRIVATE KEY|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" "$1"' \
  _ "$_M05_ENV/terraform.tfvars"

# --- Les garde-fous refusent au plan ce qu'ils doivent refuser ----------------------------------------
# _m05_refuse ARGUMENTS… — vrai si le plan échoue sur une validation de variable.
#   (sortie capturée d'abord : avec « pipefail », le code retour 1 de tofu ferait échouer le tube)
_m05_refuse() {
  local sortie
  sortie="$(_m05_tofu plan -refresh=false -lock=false -input=false -no-color "$@" 2>&1)" || true
  grep -q 'Invalid value for variable' <<<"$sortie"
}
_m05_accepte_tfvars() { ! _m05_refuse -compact-warnings; }
# Témoin : sans valeur imposée, les valeurs du lab passent les validations (sinon tous les
# refus ci-dessous seraient de faux positifs).
check_cmd "témoin : les valeurs de terraform.tfvars passent les validations" _m05_accepte_tfvars
check_cmd "refusé : VMID hors de la plage 2050-2059 (1004 = git01)" \
  _m05_refuse -var 'vm_essai={vmid=1004, nom="m05-essai"}'
check_cmd "refusé : nom de VM invalide (M05_Essai)" _m05_refuse -var 'vm_essai={vmid=2050, nom="M05_Essai"}'
check_cmd "refusé : mémoire hors règle (1000 Mo)" \
  _m05_refuse -var 'vm_essai={vmid=2050, nom="m05-essai", memoire_mo=1000}'
check_cmd "refusé : disque plus petit que celui de l'image (8 Go)" \
  _m05_refuse -var 'vm_essai={vmid=2050, nom="m05-essai", disque_go=8}'
check_cmd "refusé : aucune clé SSH" _m05_refuse -var 'cles_ssh_admin=[]'
check_cmd "refusé : une clé privée à la place d'une clé publique" \
  _m05_refuse -var 'cles_ssh_admin=["-----BEGIN OPENSSH PRIVATE KEY-----"]'
check_cmd "refusé : étiquette réservée (socle)" _m05_refuse -var 'etiquettes_supplementaires=["socle"]'
check_cmd "refusé : étiquette réservée (role-dns)" _m05_refuse -var 'etiquettes_supplementaires=["role-dns"]'
check_cmd "refusé : un autre pool que lab" _m05_refuse -var 'pool=production'
check_cmd "refusé : un autre VNet que vsandbox" _m05_refuse -var 'vnet=vinfra'

# --- Sortie et plan ---------------------------------------------------------------------------------------
if _m05_backend_distant; then
  skip "sortie essai dans l'état" "état de envs/lab-m05 sur un backend distant : voir lab/bin/check 05 11"
else
  check_output "sortie essai : VMID 2050" '^2050$' _m05_etat '.outputs.essai.value.vmid // empty'
  check_output "sortie essai : nom complet m05-essai.par1.medisphere.internal" \
    '^m05-essai\.par1\.medisphere\.internal$' _m05_etat '.outputs.essai.value.fqdn // empty'
  check_output "sortie essai : adresse IPv4 du VLAN 99" '^10\.10\.99\.[0-9]+$' \
    _m05_etat '.outputs.essai.value.ipv4 // empty'
fi
_m05_controles_etat_et_plan "l'état connaît toujours la VM d'essai (refactoring sans recréation)" \
  '[.resources[]? | select(.mode == "managed" and .type == "proxmox_virtual_environment_vm")
    | .instances[].attributes.vm_id] | index(2050) != null'
