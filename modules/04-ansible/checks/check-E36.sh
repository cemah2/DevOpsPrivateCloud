# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E36.sh — M04-E36 « Panne : le playbook passe mais rien ne change » : le réglage demandé
# (bannière légale, Banner) est effectif sur dns01, il vient du rôle, et rien ne détourne plus le
# playbook (copie de rôle, filtre d'étiquettes, mauvaise cible). Lecture seule.

# shellcheck source=_m04-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-expert.sh"

title "M04-E36 — Le rôle ssh_durci s'applique vraiment à dns01"
require_cmd ssh jq

# Aucun rôle de playbooks/roles/ ne porte le nom d'un rôle de roles/ (il serait pris à sa place).
_m04_e36_pas_de_copie() {
  local r
  for r in "$_m04x_src"/playbooks/roles/*/; do
    [[ -d "$r" ]] || continue
    [[ -d "$_m04x_src/roles/$(basename "$r")" ]] && return 1
  done
  return 0
}

_m04_e36_pas_de_filtre() {
  local d
  d="$(_m04x_ansible ansible-config dump --only-changed 2>/dev/null)" || return 1
  ! grep -Eq '^TAGS_(RUN|SKIP)\(' <<<"$d"
}

_m04_e36_cible() {
  _m04x_inv_host dns01 | jq -e '.ansible_host == "10.10.20.10"' >/dev/null
}

check_ssh_output "dns01 : bannière légale affichée avant l'authentification (sshd -T)" dns01 '^banner /' \
  'sudo -n sshd -T 2>/dev/null | grep -i "^banner"'
check_cmd "projet : le rôle ssh_durci définit lui-même une bannière" \
  bash -c 'grep -rEqs "^ssh_durci_banniere:[[:space:]]*[\"'"'"']?/" "$1/roles/ssh_durci/defaults" || grep -rEqis "^[[:space:]]*Banner[[:space:]]+/" "$1/roles/ssh_durci/templates"' _ "$_m04x_src"
check_ssh "dns01 : aucun fichier de configuration de sshd ne désactive la bannière" dns01 \
  '! sudo -n grep -rhEiq "^[[:space:]]*Banner[[:space:]]+none" /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config'
check_ssh "dns01 : le fichier de la bannière existe et n'est pas vide" dns01 \
  'f=$(sudo -n sshd -T 2>/dev/null | awk "tolower(\$1) == \"banner\" {print \$2}"); [ -n "$f" ] && [ "$f" != none ] && [ -s "$f" ]'
check_cmd "projet : aucune copie de rôle dans playbooks/roles/ ne masque roles/" _m04_e36_pas_de_copie
check_cmd "projet : aucun filtre d'étiquettes imposé par la configuration ([tags] run/skip)" _m04_e36_pas_de_filtre
check_cmd "inventaire : dns01 est bien 10.10.20.10" _m04_e36_cible
check_ssh "pve01 : VM de test 2040 supprimée" "$WB_PVE_HOST" '! qm status 2040 >/dev/null 2>&1'
check_cmd "panne M04-E36 close" _m04x_aucune_panne_active E36
