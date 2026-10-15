# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E27.sh — M15-E27 « Mettre à jour Cilium sans coupure »
# Lecture seule : images et état des DaemonSets/Deployments de Cilium, PDB, objets de vérification
# préalable et de test de connectivité (wb-checks) ; values, version et documentation sur main (GitLab).

# shellcheck source=_m15-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-production.sh"

title "M15-E27 — Mettre à jour Cilium sans coupure"
require_cmd kubectl jq yq curl
check_cmd "l'API de k8s-par1 répond (compte wb-checks)" _m15p_api_ok

title "Versions"
_M15_E27_AGENT="$(_m15p_get -n kube-system daemonset cilium)"
_M15_E27_OPER="$(_m15p_get -n kube-system deployment cilium-operator)"
_M15_E27_V_AGENT="$(_m15p_tag_image "$_M15_E27_AGENT" cilium-agent)"
_M15_E27_V_OPER="$(_m15p_tag_image "$_M15_E27_OPER" cilium-operator)"
check_cmd "agent Cilium en ${_M15_E27_V_AGENT:-version illisible}, au moins $_M15P_VERSION_MIN" \
  _m15p_version_min "${_M15_E27_V_AGENT:-x}" "$_M15P_VERSION_MIN"
check_output "l'opérateur est dans la même version que l'agent (${_M15_E27_V_OPER:-illisible})" \
  '^identiques$' bash -c '[ -n "$1" ] && [ "$1" = "$2" ] && echo identiques' _ "$_M15_E27_V_AGENT" "$_M15_E27_V_OPER"
check_cmd "tous les agents sont prêts et à jour" _m15p_ds_pret kube-system cilium
check_cmd "tous les Envoy (cilium-envoy) sont prêts et à jour" _m15p_ds_pret kube-system cilium-envoy
check_cmd "l'opérateur a ses réplicas prêts (au moins 2)" _m15p_deploy_pret kube-system cilium-operator 2
check_cmd "la version en service est écrite dans plateforme/k8s (main)" \
  _m15p_recherche_main plateforme/k8s "${_M15_E27_V_AGENT#v}"

title "Mise à jour sans coupure"
check_cmd "budget de perturbation de l'opérateur présent" \
  _m15p_jq "$(_m15p_get -n kube-system poddisruptionbudgets)" \
  'any(.items[]; (.metadata.name | test("operator")) or ((.spec.selector.matchLabels // {})["io.cilium/app"] == "operator"))'
check_cmd "values sur main : maxUnavailable explicite pour cilium et cilium-envoy" \
  _m15p_values_jq '(.updateStrategy.rollingUpdate.maxUnavailable != null) and (.envoy.updateStrategy.rollingUpdate.maxUnavailable != null)'
check_cmd "values sur main : budget de perturbation de l'opérateur activé" \
  _m15p_values_jq '.operator.podDisruptionBudget.enabled == true'

title "Ménage"
check_cmd "plus de DaemonSet de vérification préalable" _m15p_absent -n kube-system daemonset cilium-pre-flight-check
check_cmd "plus de Deployment de vérification préalable" _m15p_absent -n kube-system deployment cilium-pre-flight-check
_m15_e27_tests() {
  local ns
  ns="$(kube get namespaces -o json 2>/dev/null)" || return 1
  [[ -n "$ns" ]] && ! jq -e 'any(.items[]; .metadata.name | test("cilium-test"))' <<<"$ns" >/dev/null 2>&1
}
check_cmd "plus d'espace de test de connectivité (*cilium-test*)" _m15_e27_tests

title "Documentation"
check_cmd "RB-153 sur main (docs/kubernetes/reseau) : vérification préalable, retour arrière, mesures" \
  _m15p_doc_prefixe docs/kubernetes/reseau RB-153 'pr[eé]-?flight|vérification préalable' 'rollback|retour arrière' '[0-9]+ ?(s|min)\b'
check_cmd "fiche CHG-1627 sur main (docs/kubernetes/changements)" _m15p_doc_prefixe docs/kubernetes/changements CHG-1627
