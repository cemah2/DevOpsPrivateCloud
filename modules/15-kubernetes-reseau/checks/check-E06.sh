# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E06.sh — M15-E06 : Premières politiques réseau : tout interdire par défaut
# À lancer depuis adm01. Lecture seule : NetworkPolicy et pods de wb-essais (wb-checks), NodePort echo-np.
# Les politiques sont contrôlées sur leur CONTENU (ce qu'elles sélectionnent et autorisent), quel que
# soit leur nom ; le comportement est contrôlé par le seul flux observable depuis adm01 (NodePort).

# shellcheck source=_m15-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-decouverte.sh"

title "M15-E06 — Premières politiques réseau : tout interdire par défaut"
require_cmd kubectl jq curl

_m15d_e06_np="$(_m15d_get -n "$_M15D_NS" networkpolicies)"
_m15d_e06_pods="$(_m15d_get -n "$_M15D_NS" pods)"

# --- Refus par défaut ------------------------------------------------------------------------------------
check_cmd "une politique sélectionne TOUS les pods en entrée et en sortie, sans aucune autorisation" \
  _m15d_json "$_m15d_e06_np" 'any(.items[]; .spec.podSelector == {}
    and ((.spec.policyTypes // []) | sort) == ["Egress", "Ingress"]
    and ((.spec.ingress // []) | length) == 0 and ((.spec.egress // []) | length) == 0)'

# --- DNS --------------------------------------------------------------------------------------------------
check_cmd "tous les pods peuvent joindre kube-dns (kube-system, k8s-app=kube-dns) en UDP ET TCP 53, et rien d'autre par cette règle" \
  _m15d_json "$_m15d_e06_np" 'any(.items[]; .spec.podSelector == {} and any(.spec.egress[]?;
      ((.to // []) | length) == 1
      and .to[0].namespaceSelector.matchLabels["kubernetes.io/metadata.name"] == "kube-system"
      and .to[0].podSelector.matchLabels["k8s-app"] == "kube-dns"
      and ([.ports[]? | "\(.protocol // "TCP")/\(.port)"] | sort) == ["TCP/53", "UDP/53"]))'
check_cmd "aucune règle de sortie n'ouvre « tout » (to vide ou absent) dans wb-essais" \
  _m15d_json "$_m15d_e06_np" 'all(.items[]; all(.spec.egress[]?; ((.to // []) | length) > 0))'

# --- Clients → echo ---------------------------------------------------------------------------------------
check_cmd "les pods role=client peuvent sortir vers app=echo sur le port 8080 (port du pod, pas du Service)" \
  _m15d_json "$_m15d_e06_np" 'any(.items[]; .spec.podSelector.matchLabels.role == "client" and any(.spec.egress[]?;
      any(.to[]?; .podSelector.matchLabels.app == "echo" and (.namespaceSelector == null))
      and any(.ports[]?; (.port == 8080 or .port == "http") and (.protocol // "TCP") == "TCP")))'
check_cmd "echo accepte les pods role=client sur 8080" \
  _m15d_json "$_m15d_e06_np" 'any(.items[]; .spec.podSelector.matchLabels.app == "echo" and any(.spec.ingress[]?;
      any(.from[]?; .podSelector.matchLabels.role == "client" and (.namespaceSelector == null))
      and any(.ports[]?; .port == 8080 or .port == "http")))'
check_cmd "echo accepte le VLAN d'administration 10.10.10.0/24 sur 8080 (ipBlock), et pas plus large" \
  _m15d_json "$_m15d_e06_np" 'any(.items[]; .spec.podSelector.matchLabels.app == "echo" and any(.spec.ingress[]?;
      any(.from[]?; .ipBlock.cidr == "10.10.10.0/24") and any(.ports[]?; .port == 8080 or .port == "http")))
    and all(.items[]; all(.spec.ingress[]?; all(.from[]?; (.ipBlock.cidr // "") as $c
      | ($c == "" or ($c | test("/(2[4-9]|3[0-2])$"))))))'

# --- Les labels des sondes -----------------------------------------------------------------------------------
check_cmd "sonde-w01a et sonde-w02 portent role=client" _m15d_json "$_m15d_e06_pods" \
  '[.items[] | select(.metadata.name == "sonde-w01a" or .metadata.name == "sonde-w02") | .metadata.labels.role // ""] == ["client", "client"]'
check_cmd "sonde-w01b ne porte pas role=client (témoin refusé)" _m15d_json "$_m15d_e06_pods" \
  'any(.items[]; .metadata.name == "sonde-w01b" and (.metadata.labels.role // "") != "client")'

# --- Le seul flux visible depuis adm01 ---------------------------------------------------------------------
mapfile -t _m15d_e06_noeuds < <(_m15d_noeuds_echo)
_m15d_e06_ip="$(_m15d_ip_noeud "${_m15d_e06_noeuds[0]:-k8s-w01}")"
check_http "adm01 joint toujours echo par le NodePort ($_m15d_e06_ip:30880)" "http://$_m15d_e06_ip:30880/hostname" 200
