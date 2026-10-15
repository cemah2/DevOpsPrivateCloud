# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E11.sh — M15-E11 : BGP : annoncer les services à la bordure
# À lancer depuis adm01. Lecture seule (kube get, vtysh show sur gw01/gw02, GitLab, curl).

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E11 — BGP : annoncer les services à la bordure"
require_cmd kubectl jq curl

_m15o_cc="$(_m15o_kjson ciliumbgpclusterconfig bgp-par1)"
_m15o_pc="$(_m15o_kjson ciliumbgppeerconfig bordure)"
_m15o_adv="$(_m15o_kjson ciliumbgpadvertisements)"
_m15o_noeuds="$(_m15o_kjson nodes)"
_m15o_nc="$(_m15o_kjson ciliumbgpnodeconfigs)"

# --- Objets Cilium ------------------------------------------------------------------------------------
check_cmd "bgp-par1 : nœuds sélectionnés par bgp=par1, instance en AS 65040" \
  _m15o_jq "$_m15o_cc" '.spec.nodeSelector.matchLabels.bgp == "par1" and any(.spec.bgpInstances[]?; .localASN == 65040)'
check_cmd "bgp-par1 : voisins 10.10.40.2 et 10.10.40.3 en AS 65000, configuration « bordure »" \
  _m15o_jq "$_m15o_cc" '[.spec.bgpInstances[]?.peers[]? | select(.peerASN == 65000 and .peerConfigRef.name == "bordure") | .peerAddress] | sort == ["10.10.40.2","10.10.40.3"]'
check_cmd "bordure : famille ipv4/unicast qui sélectionne des annonces par étiquette" \
  _m15o_jq "$_m15o_pc" 'any(.spec.families[]?; .afi == "ipv4" and .safi == "unicast" and ((.advertisements.matchLabels // {}) | length) > 0)'
_m15o_sel="$(jq -c '[.spec.families[]? | select(.afi == "ipv4") | .advertisements.matchLabels][0] // {}' <<<"$_m15o_pc" 2>/dev/null || echo '{}')"
check_cmd "une CiliumBGPAdvertisement sélectionnée par « bordure » annonce les adresses LoadBalancerIP" \
  _m15o_jq "$_m15o_adv" --argjson s "$_m15o_sel" \
  '$s != {} and any(.items[]?; (.metadata.labels // {}) as $l | ($s | to_entries | all(.value == $l[.key])) and any(.spec.advertisements[]?; .advertisementType == "Service" and ((.service.addresses // []) | index("LoadBalancerIP"))))'

# --- Nœuds et sessions -----------------------------------------------------------------------------------
_m15o_bgp_noeuds="$(jq -r '[.items[]? | select(.metadata.labels.bgp == "par1") | .metadata.name] | sort | join(" ")' <<<"$_m15o_noeuds" 2>/dev/null || true)"
check_output "seuls les travailleurs portent bgp=par1 (portent l'étiquette : ${_m15o_bgp_noeuds:-aucun})" \
  '^k8s-w01 k8s-w02 k8s-w03$' echo "$_m15o_bgp_noeuds"
for _m15o_n in k8s-w01 k8s-w02 k8s-w03; do
  check_cmd "$_m15o_n : sessions établies avec gw01 et gw02" _m15o_jq "$_m15o_nc" --arg n "$_m15o_n" \
    '[.items[]? | select(.metadata.name == $n) | .status.bgpInstances[]?.peers[]? | select(.peeringState == "established") | .peerAddress] | sort == ["10.10.40.2","10.10.40.3"]'
done
check_cmd "aucun nœud de contrôle n'a de configuration BGP" _m15o_jq "$_m15o_nc" \
  '[.items[]?.metadata.name | select(startswith("k8s-cp"))] | length == 0'

# --- Bordure ---------------------------------------------------------------------------------------------
for _m15o_gw in gw01 gw02; do
  _m15o_sum="$(_m15o_vtysh "$_m15o_gw" 'show bgp ipv4 unicast summary json')"
  check_cmd "$_m15o_gw : trois voisins 10.10.40.61-63 établis (AS 65040)" _m15o_jq "$_m15o_sum" \
    '[(.peers // {}) | to_entries[] | select((.key | test("^10\\.10\\.40\\.6[1-3]$")) and .value.remoteAs == 65040 and .value.state == "Established")] | length == 3'
  _m15o_rt="$(_m15o_vtysh "$_m15o_gw" 'show ip route 10.10.41.20/32 json')"
  check_cmd "$_m15o_gw : route BGP 10.10.41.20/32 avec plusieurs prochains sauts (ECMP)" _m15o_jq "$_m15o_rt" \
    '[.["10.10.41.20/32"][]? | select(.protocol == "bgp" and (.selected // false)) | .nexthops[]? | select(.active // false)] | length >= 2'
  _m15o_conf="$(_m15o_vtysh "$_m15o_gw" 'show running-config')"
  check_cmd "$_m15o_gw : groupe K8S ouvert (plus de « neighbor K8S shutdown »)" \
    bash -c 'grep -q "peer-group K8S" <<<"$1" && ! grep -qE "^ *neighbor K8S shutdown" <<<"$1"' _ "$_m15o_conf"
  check_cmd "$_m15o_gw : politiques d'entrée et de sortie du groupe K8S en place" \
    bash -c 'grep -qE "neighbor K8S route-map RM-K8S-IN in" <<<"$1" && grep -qE "neighbor K8S route-map RM-K8S-OUT out" <<<"$1"' _ "$_m15o_conf"
done

# --- Joignabilité depuis le lab ----------------------------------------------------------------------
check_http "http://10.10.41.20/hostname répond depuis adm01 (route BGP)" "http://10.10.41.20/hostname" 200

# --- Code -----------------------------------------------------------------------------------------------
check_cmd "objets BGP dans composants/cilium/bgp/ de plateforme/k8s (main)" \
  bash -c '[[ $(wc -l <<<"$1") -ge 3 ]]' _ "$(_m15o_arbre_main "$_M15O_K8S" composants/cilium/bgp)"
_m15o_frr="$(_m15o_contenu_main "$_M15O_ANSIBLE" inventories/lab/group_vars/role_routeur/frr.yml)"
check_cmd "frr.yml sur main de plateforme/ansible : groupe K8S sans shutdown" \
  bash -c 'grep -q "listen range 10.10.40.0/24 peer-group K8S" <<<"$1" && ! grep -qE "neighbor K8S shutdown" <<<"$1"' _ "$_m15o_frr"
check_cmd "journal ~/m15/e11/journal.md rédigé (mesures, au moins 15 lignes)" _m15o_journal "$_M15O_TRAVAIL/e11/journal.md" 15
