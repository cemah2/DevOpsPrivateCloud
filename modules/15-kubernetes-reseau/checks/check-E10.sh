# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E10.sh — M15-E10 : LB IPAM : des adresses de service en 10.10.41.0/24
# À lancer depuis adm01. Lecture seule (kube get, GitLab, curl depuis un nœud en SSH).

# shellcheck source=_m15-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-operationnel.sh"

title "M15-E10 — LB IPAM : des adresses de service en 10.10.41.0/24"
require_cmd kubectl jq

_m15o_pools="$(_m15o_kjson ciliumloadbalancerippools)"
_m15o_pool="$(jq -c '[.items[]? | select(.metadata.name == "lb-par1")][0] // {}' <<<"$_m15o_pools")"
_m15o_svcs="$(_m15o_kjson services -A)"

# --- Pool ------------------------------------------------------------------------------------------
check_cmd "le pool lb-par1 existe" _m15o_jq "$_m15o_pool" '.metadata.name == "lb-par1"'
check_cmd "lb-par1 couvre exactement 10.10.41.10-10.10.41.199 (un seul bloc start/stop)" \
  _m15o_jq "$_m15o_pool" '(.spec.blocks | length) == 1 and .spec.blocks[0].start == "10.10.41.10" and .spec.blocks[0].stop == "10.10.41.199"'
check_cmd "lb-par1 est actif (non désactivé)" _m15o_jq "$_m15o_pool" '(.spec.disabled // false) == false'
check_output "lb-par1 n'est pas en conflit avec un autre pool" '^(False|)$' \
  _m15o_condition "$_m15o_pool" cilium.io/PoolConflict
check_output "lb-par1 est le seul pool du cluster (pools : $(jq -r '[.items[]?.metadata.name] | join(" ")' <<<"$_m15o_pools" 2>/dev/null || true))" \
  '^1$' jq -r '.items | length' <<<"$_m15o_pools"

# --- Services d'essai --------------------------------------------------------------------------------
_m15o_ip() { jq -r --arg n "$1" --arg e "${2:-wb-essais}" '[.items[]? | select(.metadata.namespace == $e and .metadata.name == $n) | .status.loadBalancer.ingress[]?.ip][0] // ""' <<<"$_m15o_svcs"; }
check_output "wb-essais/essai-lb a l'adresse demandée 10.10.41.20" '^10\.10\.41\.20$' _m15o_ip essai-lb
_m15o_a="$(_m15o_ip essai-lb-a)"; _m15o_b="$(_m15o_ip essai-lb-b)"
check_cmd "essai-lb-a et essai-lb-b partagent une même adresse du pool (${_m15o_a:-aucune} / ${_m15o_b:-aucune})" \
  bash -c '[[ -n "$1" && "$1" == "$2" && "$1" == 10.10.41.* ]]' _ "$_m15o_a" "$_m15o_b"

# --- 10.10.41.10 réservée à gw-par1 --------------------------------------------------------------------
_m15o_occupant="$(jq -r '[.items[]? | select(any(.status.loadBalancer.ingress[]?; .ip == "10.10.41.10")) | "\(.metadata.namespace)/\(.metadata.name)"] | join(" ")' <<<"$_m15o_svcs" 2>/dev/null || true)"
check_cmd "10.10.41.10 n'est occupée par aucun Service autre que celui de gw-par1 (occupant : ${_m15o_occupant:-aucun})" \
  bash -c '[[ -z "$1" || "$1" == "passerelles/cilium-gateway-gw-par1" ]]' _ "$_m15o_occupant"
_m15o_gwe="$(_m15o_kjson gateway gw-essai -n wb-essais)"
if _m15o_jq "$_m15o_gwe" '.metadata.name == "gw-essai"'; then
  check_cmd "gw-essai a l'adresse 10.10.41.11" _m15o_jq "$_m15o_gwe" 'any(.status.addresses[]?; .value == "10.10.41.11")'
else
  skip "gw-essai a l'adresse 10.10.41.11" "gw-essai supprimée"
fi

# --- Joignabilité depuis un nœud (eBPF de Cilium) ---------------------------------------------------
_m15o_noeud="$(awk '{print $1}' <<<"${WB_K8S_WORKERS:-k8s-w01}")"
check_ssh "essai-lb répond sur 10.10.41.20 depuis $_m15o_noeud" "$_m15o_noeud" \
  "curl -fsS --max-time 5 http://10.10.41.20/hostname >/dev/null"

# --- Code et journal ---------------------------------------------------------------------------------------
check_cmd "composants/cilium/lb-ipam/lb-par1.yaml est sur main de plateforme/k8s" \
  _m15o_fichier_main "$_M15O_K8S" composants/cilium/lb-ipam/lb-par1.yaml
check_cmd "journal ~/m15/e10/journal.md rédigé (au moins 10 lignes)" _m15o_journal "$_M15O_TRAVAIL/e10/journal.md" 10
