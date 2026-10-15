# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E20.sh — M14-E20 : Diagnostiquer un pod
# À lancer depuis adm01. Lecture seule : metrics-server, APIService, métriques (« kube »).

# shellcheck source=_m14-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m14-operationnel.sh"

title "M14-E20 — Diagnostiquer un pod"
require_cmd jq kubectl

_m14o_e20_d="$(_m14o_k get deployment metrics-server -n kube-system -o json)"
check_cmd "metrics-server : deux réplicas disponibles dans kube-system" _m14o_json "$_m14o_e20_d" \
  '.spec.replicas >= 2 and .status.availableReplicas >= 2'
check_cmd "metrics-server : chart 3.14.0 (étiquette helm.sh/chart)" _m14o_json "$_m14o_e20_d" \
  '.metadata.labels["helm.sh/chart"] == "metrics-server-3.14.0"'
check_cmd "API metrics.k8s.io disponible (APIService v1beta1.metrics.k8s.io)" \
  _m14o_json "$(_m14o_k get apiservice v1beta1.metrics.k8s.io -o json)" 'any(.status.conditions[]; .type == "Available" and .status == "True")'
_m14o_e20_nb="$(_m14o_k get nodes -o json | jq '.items | length' 2>/dev/null || echo 0)"
check_cmd "kubectl top node répond pour tous les nœuds ($_m14o_e20_nb)" \
  _m14o_json "$(_m14o_k get --raw /apis/metrics.k8s.io/v1beta1/nodes)" '(.items | length) == $n and $n >= 6' --argjson n "${_m14o_e20_nb:-0}"

_m14o_e20_p="$(_m14o_k get pods -n wb-essais -l medisphere.internal/exercice=e20 -o json)"
check_cmd "les cinq pods diag-* sont présents" _m14o_json "$_m14o_e20_p" \
  '[.items[].metadata.name | select(startswith("diag-"))] | sort == ["diag-config","diag-crash","diag-memoire","diag-pret","diag-sans-shell"]'
for _m14o_e20_x in diag-config diag-crash diag-memoire diag-pret diag-sans-shell; do
  check_cmd "$_m14o_e20_x : Running et prêt" _m14o_json "$_m14o_e20_p" \
    'any(.items[]; .metadata.name == $n and .status.phase == "Running"
      and any(.status.conditions[]; .type == "Ready" and .status == "True"))' --arg n "$_m14o_e20_x"
done
check_cmd "diag-memoire : stable (aucun redémarrage depuis sa réparation)" _m14o_json "$_m14o_e20_p" \
  'any(.items[]; .metadata.name == "diag-memoire" and all(.status.containerStatuses[]; .restartCount == 0))'

_m14o_e20_ns="$(_m14o_k get namespace wb-diagnostic -o json)"
check_cmd "wb-diagnostic existe en Pod Security privileged" _m14o_json "$_m14o_e20_ns" \
  '.metadata.labels["pod-security.kubernetes.io/enforce"] == "privileged"'
check_cmd "aucun pod ne reste dans wb-diagnostic" _m14o_json "$(_m14o_k get pods -n wb-diagnostic -o json)" '.items | length == 0'
check_cmd "aucun pod de diagnostic de nœud (node-debugger-*) ne traîne ailleurs" \
  _m14o_json "$(_m14o_k get pods -A -o json)" '[.items[] | select(.metadata.name | startswith("node-debugger-"))] | length == 0'
check_cmd "plateforme/k8s : composants/metrics-server/values.yaml sur main" \
  _m14o_fichier_main "$_M14O_P_K8S" composants/metrics-server/values.yaml
for _m14o_e20_x in diag-config diag-crash diag-memoire diag-pret diag-sans-shell; do
  check_output "journal ~/m14/e20/journal.md : $_m14o_e20_x traité" "$_m14o_e20_x" cat "$_M14O_TRAVAIL/e20/journal.md"
done
