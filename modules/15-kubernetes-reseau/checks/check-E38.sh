# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E38.sh — M15-E38 « Panne : l'adresse du LoadBalancer est injoignable » : pool LB IPAM actif,
# aucun Service en attente d'adresse, configuration BGP conforme, routes des services sur les DEUX
# passerelles, Gateway joignable depuis adm01. Lecture seule.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

title "M15-E38 — Les adresses de service sont attribuées et annoncées"
require_cmd kubectl jq ssh

check_cmd "pool $_m15x_pool actif, bloc 10.10.41.10-10.10.41.199" \
  _m15x_jq '(.spec.disabled // false) == false and ([.spec.blocks[]? | select(.start == "10.10.41.10" and .stop == "10.10.41.199")] | length == 1)' \
  ciliumloadbalancerippool "$_m15x_pool"
check_cmd "aucun Service LoadBalancer sans adresse (EXTERNAL-IP <pending>)" \
  _m15x_jq '[.items[] | select(.spec.type == "LoadBalancer" and ((.status.loadBalancer.ingress // []) | length == 0))] | length == 0' svc -A
check_cmd "la Gateway $_m15x_gw a l'adresse $_m15x_gw_ip" \
  _m15x_jq "[.status.addresses[]?.value] | index(\"$_m15x_gw_ip\") != null" -n "$_m15x_gw_ns" gateway "$_m15x_gw"
check_cmd "$_m15x_bgp : AS local 65040, voisins 10.10.40.2 et 10.10.40.3 en AS 65000" \
  _m15x_jq '.spec.bgpInstances | length > 0 and all(.localASN == 65040)
    and ([.[].peers[]? | select(.peerASN == 65000) | .peerAddress | sub("/32$"; "")] | index("10.10.40.2") != null and index("10.10.40.3") != null)' \
  ciliumbgpclusterconfig "$_m15x_bgp"
_m15_e38_sel="$(kube get ciliumbgpclusterconfig "$_m15x_bgp" -o json 2>/dev/null | jq -r '.spec.nodeSelector.matchLabels // {} | to_entries | map("\(.key)=\(.value)") | join(",")')" || true
check_cmd "le sélecteur de nœuds de $_m15x_bgp désigne au moins un travailleur" \
  test -n "$_m15_e38_sel" -a -n "$(kube get nodes -l "${_m15_e38_sel:-x=y}" -o name 2>/dev/null)"
check_cmd "une CiliumBGPAdvertisement annonce les adresses LoadBalancerIP des Services" \
  _m15x_jq '[.items[].spec.advertisements[]? | select(.advertisementType == "Service") | .service.addresses[]?] | index("LoadBalancerIP") != null' \
  ciliumbgpadvertisements
for _m15_e38_g in "${_m15x_passerelles[@]}"; do
  check_ssh_output "$_m15_e38_g : PL-DEPUIS-K8S accepte les /32 de 10.10.41.0/24 (le 32)" "$_m15_e38_g" \
    'seq 10 permit 10\.10\.41\.0/24 le 32' "sudo -n vtysh -c 'show ip prefix-list PL-DEPUIS-K8S'"
  check_ssh_output "$_m15_e38_g : route BGP vers $_m15x_gw_ip dans la table du noyau" "$_m15_e38_g" \
    'proto bgp' "ip -4 route show $_m15x_gw_ip"
done
check_port "$_m15x_gw_ip:443 joignable depuis adm01" "$_m15x_gw_ip" 443
check_cmd "panne M15-E38 close (lab/bin/break 15 38 --annuler après réparation)" _m15x_aucune_panne_active E38
