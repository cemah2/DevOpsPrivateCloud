# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts « bash -c » : arguments passés en $1, $2…
# check-E44.sh — M15-E44 « Sous le capot : eBPF et les tables de Cilium » : compte rendu commité,
# sections et outils demandés, aucun reste de diagnostic, agents Cilium sains. Lecture seule.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

title "M15-E44 — Sous le capot : eBPF et les tables de Cilium"
require_cmd kubectl jq

_m15_e44_doc=docs/kubernetes/reseau/analyses/sous-le-capot-ebpf.md
check_cmd "compte rendu $_m15_e44_doc commité" _m15x_doc_commite "$_m15_e44_doc"
for _m15_e44_s in "Programmes eBPF" "Un Service vu par Cilium" "Suivi de connexion" "Identités et politiques" \
  "Suivre un paquet" "Réponses aux questions"; do
  check_cmd "section « $_m15_e44_s »" _m15x_doc_contient "$_m15_e44_doc" "^## .*$_m15_e44_s"
done
for _m15_e44_o in 'bpftool (prog|net)' 'bpf lb list' 'bpf ct list' 'bpf policy get' 'cilium-dbg monitor|hubble observe' 'bpf ipcache'; do
  check_cmd "le compte rendu cite « $_m15_e44_o »" _m15x_doc_contient "$_m15_e44_doc" "$_m15_e44_o"
done
check_cmd "le compte rendu cite l'adresse ClusterIP du Service étudié (10.96.x.x)" \
  _m15x_doc_contient "$_m15_e44_doc" '10\.96\.[0-9]{1,3}\.[0-9]{1,3}'
check_cmd "autorisations temporaires retirées (aucune politique de $_m15x_ns_app ne cite wb-pannes)" bash -c '
  a="$(kubectl --kubeconfig "$1" -n "$2" get networkpolicy -o json)" && b="$(kubectl --kubeconfig "$1" -n "$2" get cnp -o json)" || exit 1
  printf "%s\n%s\n" "$a" "$b" | jq -s -e "[.[].items[].spec | tostring | select(test(\"wb-pannes\"))] | length == 0" >/dev/null' \
  _ "${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}" "$_m15x_ns_app"
check_cmd "aucun pod de diagnostic de nœud oublié (node-debugger-*)" \
  _m15x_jq '[.items[] | select(.metadata.name | startswith("node-debugger-"))] | length == 0' pods -A
check_cmd "agents Cilium tous prêts" \
  _m15x_jq '.items | length > 0 and all(.status.conditions[]? | select(.type == "Ready") | .status == "True")' -n kube-system pods -l k8s-app=cilium
