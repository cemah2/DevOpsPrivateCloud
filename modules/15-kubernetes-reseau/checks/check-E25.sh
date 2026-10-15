# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E25.sh — M15-E25 « Haute disponibilité de l'entrée : perdre un nœud, une passerelle »
# Lecture seule : tables de routage de gw01/gw02 (SSH, ip route), CiliumBGPPeerConfig et statut des
# CiliumBGPNodeConfig (wb-checks), frr.yml et RB-152 sur main (API GitLab), Service d'essai absent.

# shellcheck source=_m15-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-production.sh"

title "M15-E25 — Haute disponibilité de l'entrée"
require_cmd kubectl jq curl
check_cmd "l'API de k8s-par1 répond (compte wb-checks)" _m15p_api_ok

title "Bordure : multichemin et route de rejet"
for _m15_e25_g in "${_M15P_PASSERELLES[@]}"; do
  check_ssh "$_m15_e25_g : $_M15P_GW_IP installée vers au moins deux nœuds (multichemin)" "$_m15_e25_g" \
    "[ \"\$(ip route show $_M15P_GW_IP | grep -c 'nexthop via 10\.10\.40\.')\" -ge 2 ]"
  check_ssh "$_m15_e25_g : route de rejet pour 10.10.41.0/24 (aucune fuite vers le WAN sans BGP)" "$_m15_e25_g" \
    'ip route show type blackhole 10.10.41.0/24 | grep -q "10.10.41.0/24"'
done
_m15_e25_frr() {
  _m15p_contient "$(_m15p_contenu_main plateforme/ansible inventories/lab/group_vars/role_routeur/frr.yml)" \
    '10\.10\.41\.0/24' 'blackhole' 'maximum_paths'
}
check_cmd "plateforme/ansible : frr.yml (role_routeur) décrit la route de rejet et le multichemin, sur main" _m15_e25_frr

title "Sessions BGP de Cilium"
_M15_E25_PEER="$(_m15p_get ciliumbgppeerconfig bordure)"
check_cmd "CiliumBGPPeerConfig bordure : redémarrage en douceur activé" \
  _m15p_jq "$_M15_E25_PEER" '.spec.gracefulRestart.enabled == true and (.spec.gracefulRestart.restartTimeSeconds // 120) <= 120'
check_cmd "CiliumBGPPeerConfig bordure : hold time explicite de 30 s au plus" \
  _m15p_jq "$_M15_E25_PEER" '(.spec.timers.holdTimeSeconds // 0) > 0 and .spec.timers.holdTimeSeconds <= 30'
_m15_e25_sessions() {
  local hold
  hold="$(jq -r '.spec.timers.holdTimeSeconds // 0' <<<"$_M15_E25_PEER" 2>/dev/null)" || return 1
  _m15p_jq "$(_m15p_get ciliumbgpnodeconfigs)" \
    '[.items[].status.bgpInstances[]?.peers[]?] as $p
     | ($p | length) >= 6
       and all($p[]; (.peeringState // "" | ascii_downcase) == "established")
       and all($p[]; (.timers.appliedHoldTimeSeconds // -1) == $h)' --argjson h "${hold:-0}"
}
check_cmd "au moins 6 sessions (3 travailleurs × 2 passerelles), toutes établies, hold time appliqué conforme" _m15_e25_sessions

title "Runbook et ménage"
check_cmd "RB-152 sur main de plateforme/medisphere (docs/kubernetes/reseau) avec les temps mesurés" \
  _m15p_doc_prefixe docs/kubernetes/reseau RB-152 'hold' 'graceful|redémarrage en douceur' '[0-9]+ ?s\b'
check_cmd "le Service d'essai wb-essais/echo-lb n'existe plus" _m15p_absent -n wb-essais service echo-lb
