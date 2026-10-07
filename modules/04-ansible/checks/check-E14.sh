# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E14.sh — M04-E14 : Boucles, conditions et filtres
# À lancer depuis adm01, APRÈS ressources/M04-E14/semer-heritage-infoger.sh et l'application
# du rôle. Lecture seule : code du rôle, valeurs calculées (module debug), comptes et clés
# sur les hôtes, playbook en --check limité aux comptes.

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E14 — Boucles, conditions et filtres"
require_cmd git jq curl

# --- Le code ----------------------------------------------------------------------------------------
check_cmd "les comptes sont décrits par une liste de données (base_utilisateurs)" \
  _m04_contient inventories/lab/group_vars/all/main.yml '^base_utilisateurs:'
check_cmd "les tâches de comptes bouclent sur cette liste (loop:)" \
  bash -c 'grep -Eq "^[[:space:]]+loop:" "$1"/roles/base/tasks/utilisateurs.yml' _ "$_M04_SRC"
check_cmd "aucune boucle with_* dans les rôles (loop: depuis ansible 2.5)" \
  bash -c '! grep -rEq "^[[:space:]]+with_[a-z]+:" "$1/roles"' _ "$_M04_SRC"
check_cmd "aucun nom de compte écrit en dur dans les tâches du rôle" \
  bash -c '! grep -Eq "name:[[:space:]]*\"?(secours|infoger)\"?[[:space:]]*$" "$1"/roles/base/tasks/utilisateurs.yml' _ "$_M04_SRC"
check_cmd "l'agent QEMU dépend des faits de virtualisation (condition)" \
  bash -c 'grep -rEq "virtualization_(type|role)" "$1"/roles/base/tasks' _ "$_M04_SRC"

# --- Les valeurs calculées -------------------------------------------------------------------------------
check_output "infoger est déclaré à supprimer (etat: absent)" '^\["absent"\]$' \
  _m04_debug dns01 "base_utilisateurs | selectattr('nom', 'equalto', 'infoger') | map(attribute='etat') | list"
check_output "la liste des refus SSH est DÉDUITE des comptes (secours y figure)" '"secours"' \
  _m04_debug dns01 "ssh_durci_utilisateurs_refuses"

# --- L'état des hôtes -----------------------------------------------------------------------------------
for _m04o_h in $_M04O_DISTANTS; do
  check_ssh "$_m04o_h : plus de compte infoger" "$_m04o_h" '! getent passwd infoger >/dev/null'
  check_ssh "$_m04o_h : plus de dossier /home/infoger" "$_m04o_h" '! test -e /home/infoger'
  check_ssh "$_m04o_h : plus aucune clé infoger@legacy pour admin" "$_m04o_h" \
    '! grep -q "infoger@legacy" ~admin/.ssh/authorized_keys'
  _m04o_n="$(_m04_debug "$_m04o_h" "base_utilisateurs | selectattr('nom', 'equalto', 'admin') | map(attribute='cles') | first | length")"
  check_ssh "$_m04o_h : admin a exactement les ${_m04o_n:-?} clé(s) déclarée(s)" "$_m04o_h" \
    "[ \"\$(grep -cE '^[^#[:space:]]' ~admin/.ssh/authorized_keys)\" = '${_m04o_n:-x}' ]"
  check_ssh "$_m04o_h : aucune clé autorisée pour secours" "$_m04o_h" \
    'h="$(getent passwd secours | cut -d: -f6)"; [ -n "$h" ] && ! sudo -n test -s "$h/.ssh/authorized_keys"'
done
check_ssh "dns01 : agent QEMU actif (VM KVM)" dns01 'systemctl is-active --quiet qemu-guest-agent'

# --- Idempotence -------------------------------------------------------------------------------------------
_m04o_sortie="$(_m04_simuler playbooks/socle-base.yml --tags base_utilisateurs)"
for _m04o_h in $_M04_SOCLE; do
  check_cmd "--check --tags base_utilisateurs sur $_m04o_h : aucun changement" _m04_recap "$_m04o_sortie" "$_m04o_h"
done
