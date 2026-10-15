# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E03.sh — M15-E03 : Services : ClusterIP, NodePort, headless et EndpointSlices
# À lancer depuis adm01. Lecture seule : Deployment, Services et EndpointSlices de wb-essais (wb-checks),
# requêtes HTTP vers le NodePort echo-np depuis adm01.

# shellcheck source=_m15-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-decouverte.sh"

title "M15-E03 — Services : ClusterIP, NodePort, headless et EndpointSlices"
require_cmd kubectl jq curl

# --- L'application echo ------------------------------------------------------------------------------
_m15d_e03_dep="$(_m15d_get -n "$_M15D_NS" deployment echo)"
check_cmd "Deployment echo : 3 réplicas prêts" _m15d_json "$_m15d_e03_dep" \
  '.spec.replicas == 3 and (.status.readyReplicas // 0) == 3'
check_cmd "echo a une sonde de disponibilité (readinessProbe)" _m15d_json "$_m15d_e03_dep" \
  '.spec.template.spec.containers[0].readinessProbe != null'
mapfile -t _m15d_e03_noeuds < <(_m15d_noeuds_echo)
_m15d_e03_partout() {
  local w
  for w in "${_M15D_WORKERS[@]}"; do
    printf '%s\n' "${_m15d_e03_noeuds[@]}" | grep -qx -- "$w" || return 1
  done
}
check_cmd "un pod echo prêt sur chacun des travailleurs ${_M15D_WORKERS[*]} (vus : ${_m15d_e03_noeuds[*]:-aucun})" \
  _m15d_e03_partout

# --- Les Services ---------------------------------------------------------------------------------------
_m15d_e03_svc="$(_m15d_get -n "$_M15D_NS" services)"
_m15d_e03_s() { _m15d_json "$_m15d_e03_svc" ".items[] | select(.metadata.name == \$n) | $2" --arg n "$1"; }
check_cmd "echo : ClusterIP dans 10.96.0.0/16, port 80 vers le port du pod (http ou 8080)" _m15d_e03_s echo \
  '.spec.type == "ClusterIP" and (.spec.clusterIP | test("^10\\.96\\.")) and (.spec.ports[0].port == 80) and (.spec.ports[0].targetPort == "http" or .spec.ports[0].targetPort == 8080)'
check_cmd "echo : affinité de session par adresse client (sessionAffinity ClientIP)" _m15d_e03_s echo \
  '.spec.sessionAffinity == "ClientIP"'
check_cmd "echo-np : NodePort 30880, externalTrafficPolicy Local" _m15d_e03_s echo-np \
  '.spec.type == "NodePort" and .spec.ports[0].nodePort == 30880 and .spec.externalTrafficPolicy == "Local"'
check_cmd "echo-local : ClusterIP, internalTrafficPolicy Local" _m15d_e03_s echo-local \
  '.spec.type == "ClusterIP" and .spec.internalTrafficPolicy == "Local"'
check_cmd "echo-sans-tete : headless (clusterIP None)" _m15d_e03_s echo-sans-tete \
  '.spec.clusterIP == "None" and (.spec.selector.app == "echo")'

# --- EndpointSlices ------------------------------------------------------------------------------------
_m15d_e03_eps="$(_m15d_get -n "$_M15D_NS" endpointslices -l kubernetes.io/service-name=echo)"
check_cmd "EndpointSlice de echo : 3 adresses prêtes, port 8080" _m15d_json "$_m15d_e03_eps" \
  '[.items[] | .endpoints[]? | select(.conditions.ready == true)] | length == 3
   and ([.items[] | .ports[]? | .port] | index(8080) != null)'
check_cmd "les adresses de l'EndpointSlice portent le nom de leur nœud (nodeName)" _m15d_json "$_m15d_e03_eps" \
  '[.items[] | .endpoints[]? | .nodeName // ""] | length == 3 and all(. != "")'

# --- Le NodePort depuis adm01 --------------------------------------------------------------------------
for _m15d_e03_n in "${_m15d_e03_noeuds[@]}"; do
  _m15d_e03_ip="$(_m15d_ip_noeud "$_m15d_e03_n")"
  check_http "NodePort echo-np sur $_m15d_e03_n ($_m15d_e03_ip:30880) répond" "http://$_m15d_e03_ip:30880/hostname" 200
done
_m15d_e03_ip="$(_m15d_ip_noeud "${_m15d_e03_noeuds[0]:-k8s-w01}")"
_m15d_e03_client="$(curl -s --max-time "${WB_TIMEOUT:-5}" "http://$_m15d_e03_ip:30880/clientip" 2>/dev/null || true)"
check_output "externalTrafficPolicy Local : le pod voit l'adresse de adm01 (10.10.10.x), pas celle d'un nœud (vu : ${_m15d_e03_client:-rien})" \
  '^10\.10\.10\.[0-9]+:' echo "$_m15d_e03_client"
_m15d_e03_cp="$(_m15d_ip_noeud "${_M15D_CP[0]}")"
_m15d_e03_code="$(_m15d_http_code "http://$_m15d_e03_cp:30880/hostname")"
_m15d_e03_code_w="$(_m15d_http_code "http://$_m15d_e03_ip:30880/hostname")"
# Le refus n'a de sens que si le NodePort répond ailleurs (sinon un cluster injoignable passerait).
check_cmd "externalTrafficPolicy Local : ${_M15D_CP[0]} (sans pod echo) ne sert pas le NodePort (HTTP ${_m15d_e03_code:-?}), un travailleur oui (HTTP ${_m15d_e03_code_w:-?})" \
  bash -c '[[ -n "$1" && "$2" == 200 && "$3" != 200 ]]' _ "$_m15d_e03_cp" "$_m15d_e03_code_w" "$_m15d_e03_code"
