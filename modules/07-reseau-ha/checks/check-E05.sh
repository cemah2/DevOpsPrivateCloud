# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les expressions entre apostrophes sont évaluées par bash -c ou sur l'hôte distant
#
# check-E05.sh — M07-E05 : Premiers pas avec Open vSwitch
# À lancer depuis adm01. Lecture seule : état de net01 en SSH (ovs-vsctl get, ovs-ofctl dump-flows,
# ip netns exec … ping), API GitLab en lecture.

# shellcheck source=_m07-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-decouverte.sh"

title "M07-E05 — Premiers pas avec Open vSwitch"
require_cmd jq curl

check_cmd "net01 : openvswitch-switch actif et lancé au démarrage" _m07d_actif net01 openvswitch-switch.service
check_cmd "net01 : m07-ovs.service actif et lancé au démarrage" _m07d_actif net01 m07-ovs.service
check_ssh "net01 : le pont OVS br-lab existe" net01 'sudo -n ovs-vsctl br-exists br-lab'

for _m07d_e05_p in ovs-a:110 ovs-c:110 ovs-b:120; do
  check_ssh_output "br-lab : ${_m07d_e05_p%%:*} est un port d'accès du VLAN ${_m07d_e05_p##*:}" net01 \
    "^${_m07d_e05_p##*:}$" "sudo -n ovs-vsctl get port ${_m07d_e05_p%%:*} tag"
done
check_ssh_output "br-lab : ovs-r est un trunk 110,120 (sans VLAN d'accès)" net01 '^\[110, 120\] \[\]$' \
  'echo "$(sudo -n ovs-vsctl get port ovs-r trunks) $(sudo -n ovs-vsctl get port ovs-r tag)"'

check_cmd "ns-a joint ns-c (même VLAN, commutation)" _m07d_ping net01 172.31.110.11 ns-a
check_cmd "ns-a joint ns-b (autre VLAN, routage par ns-r)" _m07d_ping net01 172.31.120.10 ns-a
check_cmd "ns-b joint ns-a" _m07d_ping net01 172.31.110.10 ns-b
check_ssh_output "ns-a : la route vers ns-b passe par 172.31.110.1" net01 'via 172\.31\.110\.1 ' \
  'sudo -n ip -n ns-a route get 172.31.120.10'

# Seule la règle par défaut (priority=0, actions=NORMAL) : aucun flux ajouté à la main ne reste.
check_ssh_output "br-lab : une seule règle OpenFlow, NORMAL (aucun flux manuel résiduel)" net01 '^1 1$' \
  'f=$(sudo -n ovs-ofctl dump-flows br-lab | grep "actions="); echo "$(grep -c . <<<"$f") $(grep -c "actions=NORMAL" <<<"$f")"'

check_cmd "plateforme/ansible (main) : rôle ovs_labo" _m07d_ansible_main roles/ovs_labo/tasks/main.yml
