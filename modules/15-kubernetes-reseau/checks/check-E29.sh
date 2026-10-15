# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E29.sh — M15-E29 « Mesurer les performances réseau »
# Lecture seule : ConfigMap cilium-config et DaemonSet cilium (wb-checks), values et fiche sur main.

# shellcheck source=_m15-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m15-production.sh"

title "M15-E29 — Mesurer les performances réseau"
require_cmd kubectl jq yq curl
check_cmd "l'API de k8s-par1 répond (compte wb-checks)" _m15p_api_ok

title "Le cluster est revenu à l'état de référence"
check_output "Cilium est en mode tunnel (cilium-config : routing-mode)" '^tunnel$' _m15p_cilium_cfg routing-mode
check_output "le tunnel est VXLAN (cilium-config : tunnel-protocol)" '^vxlan$' _m15p_cilium_cfg tunnel-protocol
check_output "le chiffrement WireGuard est toujours actif" '^true$' _m15p_cilium_cfg enable-wireguard
check_cmd "tous les agents Cilium sont prêts et à jour" _m15p_ds_pret kube-system cilium
check_cmd "values sur main : pas de routage natif" _m15p_values_jq '(.routingMode // "tunnel") == "tunnel" and (.autoDirectNodeRoutes // false) == false'
check_cmd "l'espace de mesure wb-perf a été supprimé" _m15p_absent namespace wb-perf

title "Documentation"
check_cmd "docs/kubernetes/reseau/performances.md sur main (protocole, référence, séries, MTU, réserves)" \
  _m15p_doc_main docs/kubernetes/reseau/performances.md 'VXLAN' 'natif' 'WireGuard' 'MTU' 'r[ée]f[ée]rence' 'r[ée]serve'
