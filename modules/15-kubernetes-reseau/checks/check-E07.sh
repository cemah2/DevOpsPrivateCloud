# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E07.sh — M15-E07 : Gateway API : premières routes HTTP
# À lancer depuis adm01. Lecture seule : CRD, GatewayClass, Gateway, HTTPRoute, politiques et Services
# (wb-checks), requêtes HTTP vers le NodePort de la Gateway d'essai, fichiers sur main (API GitLab).

# shellcheck source=_m15-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-decouverte.sh"

title "M15-E07 — Gateway API : premières routes HTTP"
require_cmd kubectl jq yq curl

# --- CRD de la Gateway API : canal standard, version figée ------------------------------------------------------
_m15d_e07_crd="$(_m15d_get crd)"
for _m15d_e07_r in gatewayclasses gateways httproutes referencegrants grpcroutes backendtlspolicies tlsroutes; do
  check_cmd "CRD $_m15d_e07_r.gateway.networking.k8s.io : canal standard, $_M15D_GW_API_VERSION" _m15d_json "$_m15d_e07_crd" \
    'any(.items[]; .metadata.name == $n
      and .metadata.annotations["gateway.networking.k8s.io/channel"] == "standard"
      and .metadata.annotations["gateway.networking.k8s.io/bundle-version"] == $v)' \
    --arg n "$_m15d_e07_r.gateway.networking.k8s.io" --arg v "$_M15D_GW_API_VERSION"
done
check_cmd "aucune CRD gateway.networking.k8s.io du canal experimental" _m15d_json "$_m15d_e07_crd" \
  'all(.items[] | select(.spec.group == "gateway.networking.k8s.io");
       .metadata.annotations["gateway.networking.k8s.io/channel"] == "standard")'

# --- Droits du compte des vérifications (ClusterRole agrégée wb-checks, M14-E06) ------------------------------------
check_output "wb-checks lit les objets de la Gateway API (wb-checks-reseau)" '^yes$' \
  kube auth can-i list gateways.gateway.networking.k8s.io --all-namespaces
check_output "wb-checks lit les objets de cert-manager (wb-checks-reseau)" '^yes$' \
  kube auth can-i list certificates.cert-manager.io --all-namespaces
# (fonction locale : « kube » est une fonction de check-lib.sh, invisible dans un « bash -c »)
_m15d_e07_secrets() { kube auth can-i get secrets --all-namespaces 2>/dev/null || true; }
check_output "wb-checks ne lit toujours pas les Secrets" '^no$' _m15d_e07_secrets
check_cmd "rbac/wb-checks-reseau.yaml sur main de plateforme/k8s" \
  test -n "$(_m15d_contenu_main "$_M15D_PROJET_K8S" rbac/wb-checks-reseau.yaml)"

# --- Contrôleur Gateway API de Cilium ----------------------------------------------------------------------------
check_output "cilium-config : enable-gateway-api = true" '^true$' _m15d_cilium_cfg enable-gateway-api
check_output "cilium-config : kube-proxy-replacement = true (exigé par la Gateway API de Cilium)" '^true$' \
  _m15d_cilium_cfg kube-proxy-replacement
check_cmd "chaque agent Cilium a redémarré après la dernière modification de cilium-config" _m15d_agents_a_jour
_m15d_e07_gc="$(_m15d_get gatewayclasses)"
check_cmd "GatewayClass cilium acceptée (contrôleur io.cilium/gateway-controller)" _m15d_json "$_m15d_e07_gc" \
  'any(.items[]; .metadata.name == "cilium" and .spec.controllerName == "io.cilium/gateway-controller"
       and any(.status.conditions[]?; .type == "Accepted" and .status == "True"))'
check_cmd "GatewayClass cilium-nodeport acceptée, paramétrée par une CiliumGatewayClassConfig" _m15d_json "$_m15d_e07_gc" \
  'any(.items[]; .metadata.name == "cilium-nodeport" and .spec.controllerName == "io.cilium/gateway-controller"
       and .spec.parametersRef.kind == "CiliumGatewayClassConfig"
       and any(.status.conditions[]?; .type == "Accepted" and .status == "True"))'
_m15d_e07_ref="$(jq -r '.items[] | select(.metadata.name == "cilium-nodeport") | "\(.spec.parametersRef.namespace // "")/\(.spec.parametersRef.name // "")"' <<<"$_m15d_e07_gc" 2>/dev/null || true)"
_m15d_e07_cgcc="$(_m15d_get -n "${_m15d_e07_ref%%/*}" ciliumgatewayclassconfig "${_m15d_e07_ref##*/}")"
check_cmd "CiliumGatewayClassConfig ${_m15d_e07_ref:-?} : Service de type NodePort" _m15d_json "$_m15d_e07_cgcc" \
  '.spec.service.type == "NodePort"'

# --- La Gateway d'essai et sa route ----------------------------------------------------------------------------------
_m15d_e07_gw="$(_m15d_get -n "$_M15D_NS" gateway gw-essai)"
check_cmd "Gateway gw-essai de classe cilium-nodeport, acceptée et programmée" _m15d_json "$_m15d_e07_gw" \
  '.spec.gatewayClassName == "cilium-nodeport"
   and any(.status.conditions[]?; .type == "Accepted" and .status == "True")
   and any(.status.conditions[]?; .type == "Programmed" and .status == "True")'
check_cmd "gw-essai : écouteur HTTP 80, routes du même espace seulement, au moins une route attachée" _m15d_json "$_m15d_e07_gw" \
  'any(.spec.listeners[]; .protocol == "HTTP" and .port == 80 and (.allowedRoutes.namespaces.from // "Same") == "Same")
   and any(.status.listeners[]?; .attachedRoutes >= 1)'
_m15d_e07_hr="$(_m15d_get -n "$_M15D_NS" httproute echo)"
check_cmd "HTTPRoute echo : nom echo.wb-essais.internal, rattachée à gw-essai" _m15d_json "$_m15d_e07_hr" \
  '(.spec.hostnames | index("echo.wb-essais.internal")) != null and any(.spec.parentRefs[]; .name == "gw-essai")'
check_cmd "HTTPRoute echo : acceptée et références résolues (Accepted, ResolvedRefs)" _m15d_json "$_m15d_e07_hr" \
  'any(.status.parents[]?; any(.conditions[]; .type == "Accepted" and .status == "True")
                         and any(.conditions[]; .type == "ResolvedRefs" and .status == "True"))'
check_cmd "Gateway d'observation gw-attente supprimée" _m15d_absent -n "$_M15D_NS" gateway gw-attente

_m15d_e07_cnp="$(_m15d_get -n "$_M15D_NS" ciliumnetworkpolicies)"
check_cmd "une CiliumNetworkPolicy autorise l'entité « ingress » (Envoy) vers echo sur 8080" _m15d_json "$_m15d_e07_cnp" \
  'any(.items[]; .spec.endpointSelector.matchLabels.app == "echo" and any(.spec.ingress[]?;
       ((.fromEntities // []) | index("ingress")) != null
       and any(.toPorts[]?.ports[]?; .port == "8080" or .port == "http")))'
check_cmd "cette autorisation n'ouvre pas echo à tout le monde (pas d'entité all/world/cluster)" _m15d_json "$_m15d_e07_cnp" \
  'all(.items[] | select(.spec.endpointSelector.matchLabels.app == "echo"); all(.spec.ingress[]?;
       ((.fromEntities // []) - ["ingress"]) == []))'

# --- De bout en bout, depuis adm01 ---------------------------------------------------------------------------------
_m15d_e07_svc="$(_m15d_get -n "$_M15D_NS" service cilium-gateway-gw-essai)"
check_cmd "Service cilium-gateway-gw-essai de type NodePort" _m15d_json "$_m15d_e07_svc" '.spec.type == "NodePort"'
_m15d_e07_port="$(jq -r '.spec.ports[]? | select(.port == 80) | .nodePort // empty' <<<"$_m15d_e07_svc" 2>/dev/null | head -n 1 || true)"
_m15d_e07_ip="$(_m15d_ip_noeud "${_M15D_WORKERS[0]}")"
_m15d_e07_url="http://$_m15d_e07_ip:${_m15d_e07_port:-0}"
check_http "GET /hostname avec Host echo.wb-essais.internal → 200 ($_m15d_e07_url)" "$_m15d_e07_url/hostname" 200 \
  -H "Host: echo.wb-essais.internal"
check_http "GET /shell (non routé) → 404 d'Envoy" "$_m15d_e07_url/shell?cmd=id" 404 -H "Host: echo.wb-essais.internal"
check_http "un autre nom d'hôte → 404" "$_m15d_e07_url/hostname" 404 -H "Host: autre.wb-essais.internal"

# --- Le code -----------------------------------------------------------------------------------------------------------
check_cmd "composants/gateway-api/$_M15D_GW_API_VERSION/ sur main de plateforme/k8s (7 CRD)" \
  bash -c '[[ "$(grep -c "^gateway\.networking\.k8s\.io_.*\.yaml$" <<<"$1")" -ge 7 ]]' _ \
  "$(_m15d_arbre_main "$_M15D_PROJET_K8S" "composants/gateway-api/$_M15D_GW_API_VERSION")"
_m15d_e07_values="$(_m15d_contenu_main "$_M15D_PROJET_K8S" composants/cilium/values.yaml)"
check_cmd "composants/cilium/values.yaml du dépôt : gatewayAPI.enabled true" \
  _m15d_yq_vrai '.gatewayAPI.enabled == true' "$_m15d_e07_values"
