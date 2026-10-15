# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts « bash -c » : arguments passés en $1, $2…
# check-E37.sh — M15-E37 « Panne : plus rien ne passe dans l'espace de noms » : le refus par défaut est
# toujours là, aucune règle de refus générale, chaque politique d'autorisation sélectionne des pods,
# l'API joint sa base. Lecture seule.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

title "M15-E37 — Le trafic autorisé passe dans $_m15x_ns_app"
require_cmd kubectl jq curl

check_cmd "NetworkPolicy de refus par défaut présente (tous les pods, Ingress et Egress, aucune autorisation)" \
  _m15x_refus_par_defaut "$_m15x_ns_app"
check_cmd "aucune politique Cilium ne refuse l'entrée à tout l'espace (ingressDeny sur tous les pods)" \
  _m15x_jq '[.items[] | select(.spec.ingressDeny != null and (.spec.endpointSelector == {} or .spec.endpointSelector == null))] | length == 0' \
  -n "$_m15x_ns_app" cnp
check_cmd "chaque NetworkPolicy à sélecteur non vide désigne au moins un pod" bash -c '
  k() { kubectl --kubeconfig "$1" -n "$2" "${@:3}"; }
  j="$(k "$1" "$2" get networkpolicy -o json)" || exit 1
  for s in $(printf "%s" "$j" | jq -r ".items[] | select((.spec.podSelector.matchLabels // {}) | length > 0) | .spec.podSelector.matchLabels | to_entries | map(\"\(.key)=\(.value)\") | join(\",\")"); do
    [ -n "$(k "$1" "$2" get pods -l "$s" -o name)" ] || exit 1
  done' _ "${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}" "$_m15x_ns_app"
check_cmd "chaque CiliumNetworkPolicy à sélecteur non vide désigne au moins un pod" bash -c '
  k() { kubectl --kubeconfig "$1" -n "$2" "${@:3}"; }
  j="$(k "$1" "$2" get cnp -o json)" || exit 1
  for s in $(printf "%s" "$j" | jq -r ".items[] | select((.spec.endpointSelector.matchLabels // {}) | length > 0) | .spec.endpointSelector.matchLabels | with_entries(select(.key | startswith(\"k8s:io.\") | not)) | to_entries | map(\"\(.key | sub(\"^k8s:\"; \"\"))=\(.value)\") | join(\",\")"); do
    [ -z "$s" ] || [ -n "$(k "$1" "$2" get pods -l "$s" -o name)" ] || exit 1
  done' _ "${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}" "$_m15x_ns_app"
check_cmd "une politique autorise encore PostgreSQL sur le port 5432" bash -c '
  { kubectl --kubeconfig "$1" -n "$2" get networkpolicy -o json; kubectl --kubeconfig "$1" -n "$2" get cnp -o json; } \
    | jq -s -e "[.[].items[].spec | .. | objects | select(has(\"port\")) | .port | tostring] | index(\"5432\")" >/dev/null' \
  _ "${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}" "$_m15x_ns_app"
check_cmd "https://$_m15x_hote/pret répond 200 depuis adm01 (API, base et cache joignables)" _m15x_https_stable 3
check_cmd "panne M15-E37 close (lab/bin/break 15 37 --annuler après réparation)" _m15x_aucune_panne_active E37
