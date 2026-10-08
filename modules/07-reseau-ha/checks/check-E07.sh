# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les expressions entre apostrophes sont évaluées par bash -c ou sur l'hôte distant
#
# check-E07.sh — M07-E07 : BGP avec FRR : sessions et politiques
# À lancer depuis adm01. Lecture seule : état des routeurs en SSH (vtysh « show … », ip route),
# copie de travail ~/src/ansible, API GitLab en lecture. Le mot de passe BGP est lu en mémoire pour
# vérifier qu'il n'est pas en clair dans le dépôt ; il n'est jamais affiché.

# shellcheck source=_m07-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m07-decouverte.sh"

title "M07-E07 — BGP avec FRR : sessions et politiques"
require_cmd jq curl

# routeur:AS:identifiant:voisins attendus (séparés par des virgules)
for _m07d_e07_v in "spine01:65100:10.10.255.1:10.10.250.1,10.10.250.3" "spine02:65100:10.10.255.2:10.10.250.5,10.10.250.7" \
  "leaf01:65101:10.10.255.11:10.10.250.0,10.10.250.4" "leaf02:65102:10.10.255.12:10.10.250.2,10.10.250.6"; do
  IFS=: read -r _m07d_e07_r _m07d_e07_as _m07d_e07_id _m07d_e07_voisins <<<"$_m07d_e07_v"

  check_ssh_output "$_m07d_e07_r : bgpd tourne, ospfd non" "$_m07d_e07_r" '^bgpd:oui ospfd:non$' \
    'echo "bgpd:$(pgrep -x bgpd >/dev/null && echo oui || echo non) ospfd:$(pgrep -x ospfd >/dev/null && echo oui || echo non)"'

  _m07d_e07_sum="$(_m07d_vtysh "$_m07d_e07_r" 'show bgp ipv4 unicast summary json')"
  check_cmd "$_m07d_e07_r : AS $_m07d_e07_as, identifiant $_m07d_e07_id" \
    jq -e --argjson as "$_m07d_e07_as" --arg id "$_m07d_e07_id" '.as == $as and .routerId == $id' <<<"$_m07d_e07_sum"
  _m07d_e07_sessions() {
    local sum="$1" v
    for v in ${2//,/ }; do
      jq -e --arg v "$v" '.peers[$v].state == "Established"' <<<"$sum" >/dev/null || return 1
    done
    # Exactement ces voisins-là (pas de session sur vfab7, pas de voisin en trop).
    jq -e --argjson n "$(wc -w <<<"${2//,/ }")" '.peers | length == $n' <<<"$sum" >/dev/null
  }
  check_cmd "$_m07d_e07_r : sessions établies avec ${_m07d_e07_voisins//,/ et }, et aucune autre" \
    _m07d_e07_sessions "$_m07d_e07_sum" "$_m07d_e07_voisins"

  _m07d_e07_conf="$(_m07d_vtysh "$_m07d_e07_r" 'show running-config')"
  check_cmd "$_m07d_e07_r : sessions authentifiées (mot de passe TCP-MD5 configuré)" \
    bash -c 'grep -Eq "^ neighbor [^ ]+ password " <<<"$1"' _ "$_m07d_e07_conf"
  check_cmd "$_m07d_e07_r : politiques d'entrée ET de sortie appliquées (route-map … in / out)" \
    bash -c 'grep -Eq "^  neighbor [^ ]+ route-map [^ ]+ in$" <<<"$1" && grep -Eq "^  neighbor [^ ]+ route-map [^ ]+ out$" <<<"$1"' \
    _ "$_m07d_e07_conf"
  check_ssh "$_m07d_e07_r : routes BGP du noyau uniquement dans 10.10.250.0/24 et 10.10.255.0/24" "$_m07d_e07_r" \
    '! ip -4 route show proto bgp | grep -Ev "^10\.10\.25[05]\." | grep -q .'
  check_ssh_output "$_m07d_e07_r : frr.conf toujours en 640" "$_m07d_e07_r" '^640$' 'stat -c %a /etc/frr/frr.conf'
done

# ECMP : la boucle de l'autre leaf par les deux spines, apprise en BGP.
check_ssh_output "leaf01 : 10.10.255.12 par deux chemins BGP (ECMP)" leaf01 '^2 bgp$' \
  'r=$(ip route show 10.10.255.12/32); echo "$(grep -c "nexthop via" <<<"$r") $(grep -o "proto bgp" <<<"$r" | head -n 1 | cut -d" " -f2)"'
check_ssh_output "leaf02 : 10.10.255.11 par deux chemins BGP (ECMP)" leaf02 '^2 bgp$' \
  'r=$(ip route show 10.10.255.11/32); echo "$(grep -c "nexthop via" <<<"$r") $(grep -o "proto bgp" <<<"$r" | head -n 1 | cut -d" " -f2)"'
check_ssh "leaf01 : joint la boucle de leaf02 depuis sa boucle" leaf01 'ping -c 2 -W 2 -I 10.10.255.11 10.10.255.12'

# Secret : chiffré sous l'identité « lab », et absent en clair de la copie de travail.
check_cmd "Mot de passe BGP de la fabric chiffré sous l'identité « lab » (group_vars/m07_fabric/vault.yml)" \
  _m07d_vault_lab inventories/lab/group_vars/m07_fabric/vault.yml
_m07d_e07_mdp_absent() {
  local mdp
  mdp="$(_m07d_vtysh spine01 'show running-config' | sed -nE 's/^ neighbor [^ ]+ password (.+)$/\1/p' | head -n 1)"
  [[ -n "$mdp" ]] || return 1
  ! grep -rqF --exclude='vault*.yml' -- "$mdp" "$_M07D_ANSIBLE/inventories" "$_M07D_ANSIBLE/playbooks" "$_M07D_ANSIBLE/roles" 2>/dev/null
}
check_cmd "Le mot de passe BGP n'apparaît en clair nulle part dans ~/src/ansible (hors fichiers Vault)" _m07d_e07_mdp_absent
