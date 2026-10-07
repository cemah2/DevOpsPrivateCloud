# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
# check-E40.sh — M04-E40 « Panne : sshd ne redémarre plus après le playbook » : sshd de runner01
# écoute, sa configuration COMPLÈTE est valide, ses clés d'hôte sont saines et reconnues par
# adm01, Ansible le joint. Lecture seule.

# shellcheck source=_m04-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-expert.sh"

title "M04-E40 — sshd de runner01"
require_cmd ssh

check_port "runner01 : port 22 ouvert" 10.10.20.15 22
check_cmd "runner01 : nouvelle connexion SSH (clé d'hôte reconnue par adm01)" _m04x_ssh_neuf runner01
check_ssh "runner01 : service ssh actif et activé" runner01 'systemctl is-active -q ssh && systemctl is-enabled -q ssh'
check_ssh "runner01 : configuration complète valide (sshd -t)" runner01 'sudo -n sshd -t'
check_ssh "runner01 : clés privées d'hôte présentes, en 600 et à root" runner01 \
  'ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 && for k in /etc/ssh/ssh_host_*_key; do [ "$(sudo -n stat -c "%a %U" "$k")" = "600 root" ] || exit 1; done'
check_ssh "runner01 : sshd n'écoute que sur des adresses de la machine" runner01 \
  'for a in $(sudo -n sshd -T | awk "/^listenaddress/ {print \$2}" | sed -E "s/:[0-9]+\$//; s/^\[//; s/\]\$//"); do case "$a" in 0.0.0.0|::) ;; *) ip -o addr | grep -qw "$a" || exit 1 ;; esac; done'
check_cmd "Ansible joint runner01 (module ping)" _m04x_ping runner01
check_ssh "runner01 : GitLab Runner toujours actif" runner01 'systemctl is-active -q gitlab-runner'
check_cmd "panne M04-E40 close" _m04x_aucune_panne_active E40
