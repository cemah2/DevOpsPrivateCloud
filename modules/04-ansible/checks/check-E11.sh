# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E11.sh — M04-E11 : Rôle ssh_durci
# À lancer depuis adm01. Lecture seule : configuration EFFECTIVE de sshd (sshd -T), nouvelles
# connexions SSH (sans multiplexage), playbook en --check limité au rôle (--tags ssh).

# shellcheck source=_m04-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-operationnel.sh"

title "M04-E11 — Rôle ssh_durci"
require_cmd git jq curl

_m04o_fic="/etc/ssh/sshd_config.d/01-ssh-durci.conf"

check_cmd "roles/ssh_durci : tasks, defaults et meta présents" _m04o_role_complet ssh_durci
check_cmd "roles/ssh_durci publié sur main" _m04_fichier_main roles/ssh_durci/tasks/main.yml
check_cmd "le fichier est validé par sshd avant d'être posé (validate: … sshd -t -f %s)" \
  bash -c 'grep -rEq "validate:.*sshd[[:space:]]+-t[[:space:]]+-f[[:space:]]+%s" "$1"/tasks' _ "$_M04_SRC/roles/ssh_durci"
check_cmd "le rôle recharge sshd (reloaded), il ne le redémarre pas" \
  bash -c 'grep -rEq "state:[[:space:]]*reloaded" "$1"/handlers && ! grep -rEq "state:[[:space:]]*restarted" "$1"/handlers' \
  _ "$_M04_SRC/roles/ssh_durci"
check_cmd "socle-base.yml applique ssh_durci" _m04_contient playbooks/socle-base.yml 'ssh_durci'

for _m04o_h in $_M04_SOCLE; do
  check_ssh_output "$_m04o_h : $_m04o_fic posé et géré par Ansible" "$_m04o_h" '[Aa]nsible' "cat $_m04o_fic"
  check_ssh "$_m04o_h : configuration complète de sshd valide (sshd -t)" "$_m04o_h" 'sudo -n sshd -t'
  for _m04o_d in 'permitrootlogin no' 'passwordauthentication no' 'kbdinteractiveauthentication no' \
    'authenticationmethods publickey' 'maxauthtries 3' 'x11forwarding no' 'allowagentforwarding no' \
    'permituserenvironment no' 'loglevel VERBOSE'; do
    check_ssh "$_m04o_h : effectif « $_m04o_d »" "$_m04o_h" "sudo -n sshd -T | grep -qix '$_m04o_d'"
  done
done
check_ssh "adm01 (bastion) : transfert TCP autorisé (ProxyJump)" adm01 'sudo -n sshd -T | grep -qix "allowtcpforwarding yes"'
for _m04o_h in $_M04O_DISTANTS; do
  check_ssh "$_m04o_h : transfert TCP refusé" "$_m04o_h" 'sudo -n sshd -T | grep -qix "allowtcpforwarding no"'
  check_cmd "$_m04o_h : une NOUVELLE connexion SSH aboutit (sans multiplexage)" \
    ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8 "$_m04o_h" true
done
check_ssh "gw01 : l'ancien fichier posé à la main (10-durcissement.conf) a été repris et retiré" gw01 \
  '! test -e /etc/ssh/sshd_config.d/10-durcissement.conf'

_m04o_sortie="$(_m04_simuler playbooks/socle-base.yml --tags ssh)"
for _m04o_h in $_M04_SOCLE; do
  check_cmd "--check --tags ssh sur $_m04o_h : aucun changement, aucun échec" _m04_recap "$_m04o_sortie" "$_m04o_h"
done
