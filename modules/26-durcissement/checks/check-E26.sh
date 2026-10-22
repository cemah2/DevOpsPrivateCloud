# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E26.sh — M26-E26 « Chiffrement transparent entre nœuds avec WireGuard »
# À lancer depuis adm01. Lecture seule : ConfigMap cilium-config, CiliumNodes, pods de l'agent
# (dates de démarrage), état de chiffrement de chaque agent (cilium-dbg status, kubeconfig
# d'administration, consultation seulement), espace wb-perf, fiche chiffrement.md sur main.

# shellcheck source=_m26-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m26-production.sh"

title "M26-E26 — Chiffrement transparent entre nœuds avec WireGuard"
require_cmd kubectl jq curl

title "Configuration de Cilium"
check_output "cilium-config : enable-wireguard = true" '^true$' _m26p_cilium_config enable-wireguard
check_output "cilium-config : encrypt-node = true (chiffrement nœud à nœud)" '^true$' _m26p_cilium_config encrypt-node
_m26_e26_sans_strict() {
  local v
  # ConfigMap illisible : pas de conclusion (sinon le contrôle passerait sur une valeur absente).
  [[ -n "$(_m26p_cilium_config enable-wireguard)" ]] || return 1
  for v in "$(_m26p_cilium_config enable-encryption-strict-mode-egress)" "$(_m26p_cilium_config enable-encryption-strict-mode-ingress)"; do
    [[ -z "$v" || "$v" == false ]] || return 1
  done
}
check_cmd "cilium-config : pas de mode strict (décision SEC-2726)" _m26_e26_sans_strict
_m26_e26_cm="$(_m26p_json -n kube-system get configmap cilium-config)"
_m26_e26_pods="$(_m26p_json -n kube-system get pods -l k8s-app=cilium)"
# Les agents doivent avoir démarré APRÈS la dernière modification de la ConfigMap (rollOutCiliumPods: false).
_m26_e26_modif="$(jq -r '[.metadata.managedFields[]?.time // empty] | max // empty' <<<"$_m26_e26_cm" 2>/dev/null || true)"
check_cmd "les six agents Cilium ont redémarré après la dernière modification de cilium-config" _m26p_jq "$_m26_e26_pods" \
  '(.items | length) == 6 and all(.items[]; (.status.startTime // "") >= $m and .status.phase == "Running")' --arg m "${_m26_e26_modif:-9999}"

title "Clés et pairs WireGuard"
_m26_e26_cn="$(_m26p_json get ciliumnodes)"
check_cmd "les six CiliumNode publient une clé publique WireGuard" _m26p_jq "$_m26_e26_cn" \
  '[.items[] | select((.metadata.annotations["network.cilium.io/wg-pub-key"] // "") != "")] | length == 6'
for _m26_e26_n in "${_M26P_NOEUDS[@]}"; do
  check_output "$_m26_e26_n : l'agent annonce WireGuard avec 5 pairs" 'Wireguard.*Peers: 5' \
    _m26p_agent "$_m26_e26_n" cilium-dbg status
done

title "Nettoyage et documentation"
check_cmd "l'espace wb-perf (pods privilégiés de mesure) n'existe plus" _m26p_absent namespace wb-perf
check_cmd "$_M26P_DOC : chiffrement.md révisé (nœud à nœud, mesures, MTU, décision)" \
  _m26p_doc_present "$_M26P_DOC" docs/kubernetes/reseau 'chiffrement\.md$' 30 \
  'nodeEncryption|nœud à nœud|noeud a noeud' 'MTU' '[0-9]+([.,][0-9]+)? ?(Gbit|Mbit)' 'contr(ô|o)le'
