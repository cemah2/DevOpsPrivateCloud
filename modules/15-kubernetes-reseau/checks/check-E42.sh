# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E42.sh — M15-E42 « Panne : les pods ne se joignent plus entre nœuds » : agents Cilium prêts
# sur tous les nœuds, aucune surcharge de configuration par nœud, aucun filtrage du tunnel ni
# interface Cilium désactivée sur les travailleurs, santé inter-nœuds complète. Lecture seule.

# shellcheck source=_m15-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-expert.sh"

title "M15-E42 — Les pods se joignent entre nœuds"
require_cmd kubectl jq ssh curl

_m15_e42_nn="$(kube get nodes -o name 2>/dev/null | wc -l)" || true
check_cmd "un agent Cilium prêt par nœud ($_m15_e42_nn nœuds)" \
  _m15x_jq "[.items[] | select(.status.conditions[]? | .type == \"Ready\" and .status == \"True\")] | length == ${_m15_e42_nn:-0} and length > 0" \
  -n kube-system pods -l k8s-app=cilium
check_cmd "aucune CiliumNodeConfig ne surcharge la configuration du tunnel" \
  _m15x_jq '[.items[] | select((.spec.defaults // {}) | keys | any(test("^tunnel")))] | length == 0' ciliumnodeconfigs -A
for _m15_e42_n in "${_m15x_travailleurs[@]}"; do
  # shellcheck disable=SC2016  # évalué sur le nœud
  check_ssh "$_m15_e42_n : aucun filtrage des ports 8472 (VXLAN) ou 51871 (WireGuard) en entrée" "$_m15_e42_n" \
    'sudo -n sh -c "{ nft list ruleset 2>/dev/null; iptables-save 2>/dev/null; }" | grep -Eiq "dport (8472|51871).*(drop|reject)" && exit 1 || exit 0'
  # shellcheck disable=SC2016
  check_ssh "$_m15_e42_n : interfaces cilium_vxlan / cilium_wg0 actives (UP) si présentes" "$_m15_e42_n" \
    'for i in cilium_vxlan cilium_wg0; do ip link show "$i" >/dev/null 2>&1 || continue; ip -o link show "$i" | grep -Eq "[<,]UP[,>]" || exit 1; done'
done
check_cmd "cilium-health (sonde forcée depuis ${_m15x_travailleurs[0]}) : tous les nœuds et points de santé joignables" \
  _m15x_sante_cilium "${_m15x_travailleurs[0]}"
check_cmd "https://$_m15x_hote/pret : 6 réponses 200 d'affilée (aucune erreur intermittente)" _m15x_https_stable 6
check_cmd "panne M15-E42 close (lab/bin/break 15 42 --annuler après réparation)" _m15x_aucune_panne_active E42
