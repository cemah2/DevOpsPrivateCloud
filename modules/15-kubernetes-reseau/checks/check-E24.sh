# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes distantes entre apostrophes
#
# check-E24.sh — M15-E24 « Chiffrer le trafic entre nœuds »
# Lecture seule : ConfigMap cilium-config, CiliumNodes, DaemonSet cilium (compte wb-checks) ; interface
# cilium_wg0 et port UDP 51871 sur chaque nœud (SSH, ip/ss) ; values et fiche sur main (API GitLab).

# shellcheck source=_m15-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-production.sh"

title "M15-E24 — Chiffrer le trafic entre nœuds"
require_cmd kubectl jq yq curl
check_cmd "l'API de k8s-par1 répond (compte wb-checks)" _m15p_api_ok

title "Configuration de Cilium"
check_output "Cilium a le chiffrement WireGuard actif (cilium-config : enable-wireguard)" '^true$' \
  _m15p_cilium_cfg enable-wireguard
check_cmd "composants/cilium/values.yaml sur main : encryption WireGuard activé" \
  _m15p_values_jq '.encryption.enabled == true and .encryption.type == "wireguard"'
check_cmd "tous les agents Cilium sont prêts et à jour (DaemonSet cilium)" _m15p_ds_pret kube-system cilium

title "Clés et interfaces"
_m15_e24_cles() {
  local n
  n="$(_m15p_nb_noeuds)"
  _m15p_jq "$(_m15p_get ciliumnodes)" \
    '(.items | length) == $n and $n > 0 and all(.items[]; (.metadata.annotations["network.cilium.io/wg-pub-key"] // "") | length > 0)' \
    --argjson n "$n"
}
check_cmd "chaque nœud a publié sa clé publique WireGuard dans son CiliumNode" _m15_e24_cles
for _m15_e24_n in "${_M15P_NOEUDS[@]}"; do
  check_ssh "$_m15_e24_n : interface cilium_wg0 présente et montée" "$_m15_e24_n" \
    'ip -o link show cilium_wg0 | grep -Eq "state (UP|UNKNOWN)|<[^>]*UP"'
  check_ssh_output "$_m15_e24_n : WireGuard écoute en UDP 51871" "$_m15_e24_n" ':51871\b' 'ss -Hnul'
done

title "Documentation"
check_cmd "docs/kubernetes/reseau/chiffrement.md sur main (décision, mesures, port 51871, ce qui n'est pas chiffré)" \
  _m15p_doc_main docs/kubernetes/reseau/chiffrement.md 'WireGuard' '51871' 'MTU' 'pas chiffr|non chiffr|en clair'
