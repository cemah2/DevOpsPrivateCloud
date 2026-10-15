# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E19.sh — M15-E19 : MetalLB en comparaison
# À lancer depuis adm01. Lecture seule : kubectl get sur le cluster d'essai (kubeconfig
# WB_M15_ESSAI_KUBECONFIG, défaut ~/.kube/m15-essai.conf), SSH vers m15-essai, curl, GitLab.

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E19 — MetalLB en comparaison"
require_cmd kubectl jq curl

_m15o_kc="${WB_M15_ESSAI_KUBECONFIG:-$HOME/.kube/m15-essai.conf}"
_m15o_essai() { kubectl --kubeconfig "$_m15o_kc" --request-timeout="${WB_TIMEOUT}s" get "$@" -o json 2>/dev/null || echo '{}'; }

# --- VM et cluster d'essai -------------------------------------------------------------------------
check_ssh "m15-essai joignable en SSH (10.10.99.51)" m15-essai "ip -4 -o addr show | grep -q ' 10\\.10\\.99\\.51/'"
check_output "kubeconfig d'essai en 600 sur adm01" '^600$' stat -c %a "$_m15o_kc"
check_cmd "le nœud m15-essai est Ready" _m15o_jq "$(_m15o_essai nodes)" \
  'any(.items[]?; .metadata.name == "m15-essai" and any(.status.conditions[]?; .type == "Ready" and .status == "True"))'
check_cmd "état OpenTofu m15-essai sur main de plateforme/infra (envs/m15-essai)" \
  bash -c '[[ -n "$1" ]]' _ "$(_m15o_arbre_main "$_M15O_INFRA" envs/m15-essai)"

# --- MetalLB -----------------------------------------------------------------------------------------
_m15o_dep="$(_m15o_essai deployments -n metallb-system)"
check_cmd "contrôleur MetalLB 0.16 prêt" _m15o_jq "$_m15o_dep" \
  'any(.items[]?; (.status.readyReplicas // 0) >= 1 and any(.spec.template.spec.containers[]?; .image | test("metallb/controller:v0\\.16\\.")))'
check_cmd "pool essai-l2 : 10.10.99.230-10.10.99.238" _m15o_jq "$(_m15o_essai ipaddresspools.metallb.io -n metallb-system)" \
  'any(.items[]?; .metadata.name == "essai-l2" and (.spec.addresses == ["10.10.99.230-10.10.99.238"] or .spec.addresses == ["10.10.99.230 - 10.10.99.238"]))'
check_cmd "annonce L2 du pool essai-l2" _m15o_jq "$(_m15o_essai l2advertisements.metallb.io -n metallb-system)" \
  'any(.items[]?; (.spec.ipAddressPools // []) | index("essai-l2"))'
_m15o_ip="$(jq -r '[.items[]? | select(.spec.type == "LoadBalancer") | .status.loadBalancer.ingress[]?.ip | select(test("^10\\.10\\.99\\.(23[0-8])$"))][0] // ""' <<<"$(_m15o_essai services -A)" 2>/dev/null || true)"
check_cmd "un Service LoadBalancer a une adresse du pool (${_m15o_ip:-aucune})" test -n "$_m15o_ip"
check_http "ce Service répond depuis adm01 (mode L2)" "http://${_m15o_ip:-10.10.99.239}/hostname" 200
check_cmd "MetalLB n'a aucun voisin BGP déclaré" _m15o_jq "$(_m15o_essai bgppeers.metallb.io -A)" '(.items // []) | length == 0'

# --- Comparaison --------------------------------------------------------------------------------------
check_cmd "m15/e19/comparaison.md : tableau MetalLB / Cilium et conclusion" \
  bash -c 'grep -qsi "metallb" "$1" && grep -qsi "cilium" "$1" && grep -qsE "^\|" "$1" && grep -qsiE "conclu" "$1"' _ "$_M15O_TRAVAIL/e19/comparaison.md"
