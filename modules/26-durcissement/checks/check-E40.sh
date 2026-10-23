# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E40.sh — M26-E40 « des nœuds ne se parlent plus » : nœuds Ready, WireGuard actif, aucun pare-feu
# d'essai, MTU cohérente, aucun nœud injoignable. Lecture seule.
# shellcheck source=_m26-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-expert.sh"

title "M26-E40 — Les nœuds communiquent de nouveau"
require_cmd jq kubectl

_e40_noeuds_ready() {
  _m26x_kq '[.items[] | select((.status.conditions[] | select(.type == "Ready") | .status) != "True")] | length == 0' nodes
}
_e40_unreachable_ok() {
  local v; v="$(_m26x_conformite_val 'max(cilium_unreachable_nodes)')"
  [[ -z "$v" ]] || [[ "${v%.*}" == 0 ]]
}

# Pare-feu d'hôte d'E27 : soit aucun nœud n'est étiqueté, soit tous le sont (un nœud retiré en douce
# n'est plus filtré par les politiques hote-*).
_e40_etiquette_coherente() {
  _m26x_kq '[.items[].metadata.labels["medisphere.internal/pare-feu-hote"] // ""] | all(. == "oui") or all(. == "")' nodes
}

check_cmd "tous les nœuds sont Ready" _e40_noeuds_ready
check_cmd "étiquette medisphere.internal/pare-feu-hote cohérente sur tous les nœuds (E27)" _e40_etiquette_coherente
check_cmd "aucune CiliumClusterwideNetworkPolicy d'essai (M26-E40) ne reste" \
  _m26x_absent ciliumclusterwidenetworkpolicies wb-pare-feu-hote-essai
_m26_e40_noeud="${WB_M26_NOEUD:-k8s-w03}"
if _m26x_ssh_ok "$_m26_e40_noeud"; then
  check_ssh "$_m26_e40_noeud : aucune table nftables d'essai (wb_e40)" "$_m26_e40_noeud" \
    "! sudo -n nft list tables 2>/dev/null | grep -q wb_e40"
  check_ssh "$_m26_e40_noeud : MTU de eth0 cohérente (≥ 1450)" "$_m26_e40_noeud" \
    "[ \"\$(cat /sys/class/net/eth0/mtu)\" -ge 1450 ]"
else
  skip "$_m26_e40_noeud" "SSH + sudo -n impossible"
fi
check_cmd "aucun nœud injoignable pour Cilium (cilium_unreachable_nodes == 0)" _e40_unreachable_ok
check_cmd "panne M26-E40 close" _m26x_aucune_panne_active E40
