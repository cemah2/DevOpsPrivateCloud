# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts « bash -c » : arguments passés en $1, $2…
# check-E35.sh — M15-E35 « Panne : le service ne répond plus » : la route de MédiAgenda recette
# est acceptée, son Service sélectionne des pods prêts sur le bon port, l'application répond.
# Lecture seule.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

title "M15-E35 — Le service de MédiAgenda recette répond"
require_cmd kubectl jq curl

_m15_e35_svc="$(_m15x_service_app)" || true
if [[ -n "$_m15_e35_svc" ]]; then
  _m15_e35_sel="$(_m15x_selecteur_service "$_m15x_ns_app" "$_m15_e35_svc")" || true
  check_cmd "route $_m15x_route acceptée par $_m15x_gw, références résolues" _m15x_route_acceptee "$_m15x_ns_app" "$_m15x_route"
  check_cmd "le port visé par la route existe sur le Service $_m15_e35_svc" bash -c '
    p="$(kubectl --kubeconfig "$1" -n "$2" get httproute "$3" -o jsonpath="{.spec.rules[0].backendRefs[0].port}")"
    kubectl --kubeconfig "$1" -n "$2" get svc "$4" -o json | jq -e --arg p "$p" "[.spec.ports[].port | tostring] | index(\$p)" >/dev/null' \
    _ "${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}" "$_m15x_ns_app" "$_m15x_route" "$_m15_e35_svc"
  check_cmd "le sélecteur du Service désigne au moins un pod" \
    test -n "$_m15_e35_sel" -a -n "$(kube -n "$_m15x_ns_app" get pods -l "${_m15_e35_sel:-x=y}" -o name 2>/dev/null)"
  check_cmd "l'EndpointSlice du Service contient au moins un point de terminaison prêt" \
    _m15x_jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length > 0' \
    -n "$_m15x_ns_app" endpointslices -l "kubernetes.io/service-name=$_m15_e35_svc"
  check_cmd "le targetPort du Service correspond à un port déclaré par les pods (8000 pour MédiAgenda)" bash -c '
    t="$(kubectl --kubeconfig "$1" -n "$2" get svc "$3" -o jsonpath="{.spec.ports[0].targetPort}")"
    kubectl --kubeconfig "$1" -n "$2" get pods -l "$4" -o json | jq -e --arg t "$t" "
      [.items[].spec.containers[].ports[]? | (.containerPort | tostring), (.name // empty)] | index(\$t)" >/dev/null' \
    _ "${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}" "$_m15x_ns_app" "$_m15_e35_svc" "${_m15_e35_sel:-x=y}"
else
  skip "route, Service et points de terminaison" "route $_m15x_ns_app/$_m15x_route introuvable"
fi
check_cmd "https://$_m15x_hote/pret répond 200 depuis adm01" _m15x_https_200 /pret
check_cmd "panne M15-E35 close (lab/bin/break 15 35 --annuler après réparation)" _m15x_aucune_panne_active E35
