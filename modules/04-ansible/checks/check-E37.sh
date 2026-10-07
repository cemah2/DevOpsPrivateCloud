# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E37.sh — M04-E37 « Panne : la variable n'a pas la valeur attendue » : tout le socle est en
# Europe/Paris, la variable de fuseau du rôle base vaut Europe/Paris pour dns01 dans un vrai jeu,
# et aucune autre valeur n'est définie ailleurs dans le projet. Lecture seule (la sonde ne lance
# qu'une tâche debug en --check, depuis un playbook temporaire retiré aussitôt).

# shellcheck source=_m04-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-expert.sh"

title "M04-E37 — Fuseau horaire du socle et précédence des variables"
require_cmd ssh

_m04_e37_var="$(_m04x_var_fuseau)" || _m04_e37_var=""

_m04_e37_effectif() {
  [[ -n "$_m04_e37_var" ]] && [[ "$(_m04x_sonde "$_m04_e37_var" dns01)" == Europe/Paris ]]
}

# Aucune autre définition de la variable (avec une autre valeur) dans le projet.
_m04_e37_une_seule_valeur() {
  [[ -n "$_m04_e37_var" ]] || return 1
  ! grep -rhE "^${_m04_e37_var}:" "$_m04x_src/inventories" "$_m04x_src/playbooks" "$_m04x_src/roles" \
      --include='*.yml' --include='*.yaml' 2>/dev/null | grep -vq 'Europe/Paris'
}

check_cmd "rôle base : variable de fuseau valant Europe/Paris trouvée (${_m04_e37_var:-aucune})" test -n "$_m04_e37_var"
check_cmd "projet : aucune autre valeur de ${_m04_e37_var:-la variable} définie (inventaire, playbooks, rôles)" _m04_e37_une_seule_valeur
check_cmd "valeur effective pour dns01 dans un jeu qui applique le rôle base : Europe/Paris" _m04_e37_effectif
for _m04_e37_h in gw01 dns01 git01 runner01; do
  check_ssh_output "$_m04_e37_h : fuseau Europe/Paris" "$_m04_e37_h" '^Europe/Paris$' 'timedatectl show -p Timezone --value'
done
check_output "adm01 : fuseau Europe/Paris" '^Europe/Paris$' timedatectl show -p Timezone --value
check_cmd "panne M04-E37 close" _m04x_aucune_panne_active E37
