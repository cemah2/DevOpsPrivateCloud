# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes ou bash -c entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E42.sh — M14-E42 « Panne : le DNS du cluster ne répond plus » : CoreDNS disponible (au moins
# deux réplicas, points d'accès prêts), Corefile cohérent (zone cluster.local, transfert vers les
# résolveurs MédiSphère), sonde DNS et agenda prêts en dnsPolicy ClusterFirst, RB-148, panne close.
# Lecture seule.

# shellcheck source=_m14-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-expert.sh"

title "M14-E42 — Le DNS du cluster répond"
require_cmd jq kubectl

if _m14x_api_repond; then
  check_cmd "coredns : au moins 2 réplicas demandés, tous disponibles" \
    _m14x_kq '(.spec.replicas // 0) >= 2 and (.status.availableReplicas // 0) == .spec.replicas' -n kube-system deploy coredns
  check_cmd "service kube-dns : au moins 2 points d'accès prêts" \
    _m14x_kq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length >= 2' \
    -n kube-system endpointslices -l kubernetes.io/service-name=kube-dns
  _m14_e42_corefile() { kube -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' 2>/dev/null; }
  check_output "Corefile : zone cluster.local servie par le greffon kubernetes" '^[[:space:]]*kubernetes cluster\.local' _m14_e42_corefile
  check_output "Corefile : transfert vers /etc/resolv.conf ou les récurseurs dns01/dns02" \
    '^[[:space:]]*forward \. +(/etc/resolv\.conf|10\.10\.20\.(10|16))( |$)' _m14_e42_corefile
  check_cmd "aucun pod coredns en CrashLoopBackOff" \
    _m14x_pods_sans '(.state.waiting.reason // "") | test("CrashLoopBackOff")' kube-system
  if _m14x_temoins; then
    check_cmd "sonde-dns (wb-pannes) prête : noms internes et MédiSphère résolus" _m14x_deploy_pret "$_m14x_ns" sonde-dns
    check_cmd "agenda (wb-pannes) disponible" _m14x_deploy_pret "$_m14x_ns" agenda
    check_cmd "agenda : dnsPolicy ClusterFirst (valeur par défaut)" \
      _m14x_kq '(.spec.template.spec.dnsPolicy // "ClusterFirst") == "ClusterFirst"' -n "$_m14x_ns" deploy agenda
  else
    skip "témoins de wb-pannes" "absents : ils sont créés à la première injection (lab/bin/break 14 42)"
  fi
else
  skip "CoreDNS et témoins" "l'API ne répond pas au compte des checks (lab/bin/check 14 39)"
fi
check_cmd "RB-148 (DNS du cluster) publié et commité" _m14x_doc_commite 'docs/kubernetes/runbooks/RB-148-*.md'
check_cmd "panne M14-E42 close (lab/bin/break 14 42 --annuler après réparation)" _m14x_aucune_panne_active E42
