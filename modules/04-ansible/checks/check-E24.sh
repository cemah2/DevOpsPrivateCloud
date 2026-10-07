# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c ou sur l'hôte distant
#
# check-E24.sh — M04-E24 « Molecule : tester un rôle sur des VMs éphémères »
# Structure Molecule sur main, droits du rôle WBAnsible, traces de tests réels (clones et
# destructions des VMID 2045 et 2046 par Proxmox), aucune instance restante, dépôt propre.

# shellcheck source=_m04-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-production.sh"

title "M04-E24 — Molecule : tester un rôle sur des VMs éphémères"
require_cmd jq ssh curl git
_m04_charger

title "Projet plateforme/ansible (branche main)"
check_cmd "configuration de base Molecule (.config/molecule/config.yml), approche ansible-native" \
  _m04_fichier_main_contient .config/molecule/config.yml '^ansible:'
for _m04_f in molecule/_commun/create.yml molecule/_commun/destroy.yml molecule/_commun/prepare.yml \
  molecule/base/molecule.yml molecule/base/verify.yml molecule/ssh_durci/molecule.yml molecule/ssh_durci/verify.yml; do
  check_cmd "$_m04_f présent sur main" _m04_fichier_main "$_m04_f"
done
check_cmd "create.yml clone par community.proxmox" \
  _m04_fichier_main_contient molecule/_commun/create.yml 'community\.proxmox\.proxmox_kvm'
check_cmd "destroy.yml contient un garde-fou avant suppression" \
  _m04_fichier_main_contient molecule/_commun/destroy.yml 'ansible\.builtin\.assert'
check_cmd "les fichiers produits par les tests sont ignorés par git (.gitignore)" \
  _m04_fichier_main_contient .gitignore 'molecule|execution\.yml|host_vars'

title "Droits du jeton wb-ansible (rôle WBAnsible)"
_m04_e24_privs="$(_m04_privileges_role WBAnsible 2>/dev/null || true)"
for _m04_p in VM.Clone VM.Allocate VM.PowerMgmt VM.Config.Cloudinit VM.GuestAgent.Audit Datastore.AllocateSpace; do
  check_cmd "WBAnsible contient $_m04_p" grep -qx -- "$_m04_p" <<<"$_m04_e24_privs"
done
# Absence d'un privilège : seulement si la liste a pu être lue (sinon le contrôle ne prouve rien).
_m04_e24_sans() { [[ -n "$_m04_e24_privs" ]] && ! grep -qx -- "$1" <<<"$_m04_e24_privs"; }
for _m04_p in VM.Console Sys.Modify Permissions.Modify VM.GuestAgent.Unrestricted; do
  check_cmd "WBAnsible ne contient pas $_m04_p" _m04_e24_sans "$_m04_p"
done

title "Tests réellement exécutés"
check_cmd "pve01 : une destruction réussie de la VM 2045 (scénario base) est journalisée" _m04_tache_pve qmdestroy 2045
check_cmd "pve01 : une destruction réussie de la VM 2046 (scénario ssh_durci) est journalisée" _m04_tache_pve qmdestroy 2046
check_cmd "aucune instance Molecule restante (VMID 2045-2049)" _m04_aucune_vm 2045 2049

title "Dépôt local"
if [[ -d "$_M04_SRC/.git" ]]; then
  check_output "git status : aucun fichier non suivi ou modifié sous molecule/" '^$' \
    git -C "$_M04_SRC" status --porcelain -- molecule .config
else
  skip "dépôt local propre" "pas de clone dans $_M04_SRC"
fi
