# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E24.sh — M29-E24 « Sous le capot : comment Chaos Mesh injecte une panne » : document publié avec
# les mécanismes et des sorties réelles, politique réseau du port gRPC du chaos-daemon, ménage de
# wb-essais (pods) et de chaos-experiences (expériences *-e24). Lecture seule.

# shellcheck source=_m29-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m29-expert.sh"

title "M29-E24 — Sous le capot de Chaos Mesh"
require_cmd kubectl jq curl

check_cmd "sous-le-capot-chaos-mesh.md : PodNetworkChaos, gRPC, netem, ipset/iptables, stress-ng et cgroup, finaliseur" \
  _m29p_doc docs/qualite '^sous-le-capot-chaos-mesh' 'PodNetworkChaos' 'gRPC' 'netem' 'ipset' 'CHAOS-(INPUT|OUTPUT)' 'stress-ng' 'cgroup' 'chaos-mesh/records' 'containerRecords'
check_cmd "sous-le-capot-chaos-mesh.md : au moins une sortie réelle de tc (qdisc netem … delay)" \
  _m29p_doc docs/qualite '^sous-le-capot-chaos-mesh' 'qdisc netem [0-9a-f]+: .*delay'
if _m29p_api_repond; then
  _m29_e24_cnp() {
    kube get ciliumnetworkpolicies.cilium.io,networkpolicies.networking.k8s.io -n chaos-mesh -o json 2>/dev/null | jq -e '
      any(.items[];
        ((.spec.endpointSelector.matchLabels // .spec.podSelector.matchLabels // {}) | tostring | test("chaos-daemon"))
        and any(.spec.ingress[]?; any(.toPorts[]?.ports[]?, .ports[]?; (.port | tostring) == "31767")
             and ((.fromEndpoints // .from // []) | tostring | test("controller-manager"))))' >/dev/null 2>&1
  }
  check_cmd "chaos-mesh : une politique réseau limite le port gRPC 31767 du daemon au contrôleur" _m29_e24_cnp
  check_cmd "wb-essais : plus aucun pod *-e24" _m29p_kq '[.items[] | select(.metadata.name | test("-e24"))] | length == 0' -n wb-essais pods
  if _m29p_lit_chaos; then
    # Les expériences d'E24 vivent dans chaos-experiences (VAP medisphere-chaos-espaces) et visent wb-essais.
    check_cmd "plus aucune expérience *-e24 (ni aucune expérience visant wb-essais encore active)" \
      bash -c '[[ "$(jq "[.[] | select((.metadata.name | test(\"e24\")) or (((.spec.selector.namespaces // []) | index(\"wb-essais\")) != null and (.status.experiment.desiredPhase // \"\") == \"Run\"))] | length" <<<"$1")" == 0 ]]' _ "$(_m29p_chaos_tous)"
  else
    skip "expériences *-e24" "le compte des checks ne lit pas chaos-mesh.org (ClusterRole wb-checks-services-m29, M29-E09)"
  fi
else
  skip "politique réseau et ménage" "l'API ne répond pas au compte des checks"
fi
