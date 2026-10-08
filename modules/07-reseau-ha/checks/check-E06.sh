# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les expressions entre apostrophes sont évaluées sur l'hôte distant
#
# check-E06.sh — M07-E06 : Routage statique puis OSPF avec FRR
# À lancer depuis adm01, à la FIN de l'exercice (avant E07, qui remplace OSPF par BGP).
# Lecture seule : état des routeurs en SSH (dpkg, stat, sysctl, vtysh « show … », ip route),
# API GitLab en lecture.

# shellcheck source=_m07-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-decouverte.sh"

title "M07-E06 — Routage statique puis OSPF avec FRR"
require_cmd jq curl

for _m07d_e06_r in $_M07D_ROUTEURS; do
  check_ssh_output "$_m07d_e06_r : FRR 10.7 du dépôt deb.frrouting.org" "$_m07d_e06_r" '^10\.7\.[0-9]+-[0-9]+~deb13' \
    'dpkg-query -W -f="\${Version}" frr'
  check_cmd "$_m07d_e06_r : service frr actif et lancé au démarrage" _m07d_actif "$_m07d_e06_r" frr.service
  check_ssh_output "$_m07d_e06_r : ospfd tourne, bgpd non" "$_m07d_e06_r" '^ospfd:oui bgpd:non$' \
    'echo "ospfd:$(pgrep -x ospfd >/dev/null && echo oui || echo non) bgpd:$(pgrep -x bgpd >/dev/null && echo oui || echo non)"'
  check_ssh_output "$_m07d_e06_r : frr.conf en frr:frr 640" "$_m07d_e06_r" '^frr:frr:640$' 'stat -c %U:%G:%a /etc/frr/frr.conf'
  check_ssh_output "$_m07d_e06_r : routage IPv4 activé" "$_m07d_e06_r" '^1$' 'sysctl -n net.ipv4.ip_forward'
done

# Voisins OSPF en état Full : 2 pour un spine, 3 pour un leaf (deux spines + vfab7).
for _m07d_e06_v in spine01:2 spine02:2 leaf01:3 leaf02:3; do
  _m07d_e06_r="${_m07d_e06_v%%:*}"
  _m07d_e06_n="$(_m07d_vtysh "$_m07d_e06_r" 'show ip ospf neighbor' | grep -c ' Full/' || true)"
  check_cmd "$_m07d_e06_r : ${_m07d_e06_v##*:} voisins OSPF en état Full (trouvé : $_m07d_e06_n)" \
    test "$_m07d_e06_n" -eq "${_m07d_e06_v##*:}"
  check_cmd "$_m07d_e06_r : eth0 (administration) n'émet pas de Hello OSPF" \
    bash -c '! grep -q "Hello due in" <<<"$1"' _ "$(_m07d_vtysh "$_m07d_e06_r" 'show ip ospf interface eth0')"
  check_cmd "$_m07d_e06_r : aucune route statique dans la configuration" \
    bash -c '! grep -q "^ip route " <<<"$1"' _ "$(_m07d_vtysh "$_m07d_e06_r" 'show running-config')"
done

# Boucle de l'autre leaf : par les deux spines, à coût égal (vfab7 plus cher).
check_ssh_output "leaf01 : 10.10.255.12 par deux chemins OSPF (ECMP via les deux spines)" leaf01 '^2 ospf$' \
  'r=$(ip route show 10.10.255.12/32); echo "$(grep -c "nexthop via 10\.10\.250\.\(0\|4\) " <<<"$r") $(grep -o "proto ospf" <<<"$r" | head -n 1 | cut -d" " -f2)"'
check_ssh_output "leaf02 : 10.10.255.11 par deux chemins OSPF (ECMP via les deux spines)" leaf02 '^2 ospf$' \
  'r=$(ip route show 10.10.255.11/32); echo "$(grep -c "nexthop via 10\.10\.250\.\(2\|6\) " <<<"$r") $(grep -o "proto ospf" <<<"$r" | head -n 1 | cut -d" " -f2)"'
check_ssh "leaf01 : joint la boucle de leaf02 depuis sa boucle" leaf01 'ping -c 2 -W 2 -I 10.10.255.11 10.10.255.12'

check_cmd "plateforme/ansible (main) : rôle frr" _m07d_ansible_main roles/frr/tasks/main.yml
check_cmd "plateforme/ansible (main) : scénario Molecule frr" _m07d_ansible_main molecule/frr/molecule.yml
check_cmd "plateforme/ansible (main) : playbook m07-fabric.yml" _m07d_ansible_main playbooks/m07-fabric.yml
