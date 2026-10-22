# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E35.sh — M21-E35 « Panne : une cible a disparu » : MédiAgenda collecté dans ses espaces, aucune
# cible node_exporter en échec, aucune politique réseau qui refuse la collecte, ServiceMonitor de
# MédiAgenda retenu par Prometheus, alertes de cible muette ET de cible disparue, RB-217, panne close.
# Lecture seule.

# shellcheck source=_m21-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-expert.sh"

title "M21-E35 — Toutes les cibles sont collectées"
require_cmd jq kubectl curl

if ! _m21x_vue_globale; then
  skip "collecte" "la vue globale ne répond pas (lab/bin/check 21 24)"
else
  for _m21_e35_ns in mediagenda-dev mediagenda-recette; do
    check_cmd "$_m21_e35_ns : cibles de MédiAgenda présentes" \
      _m21x_non_vide "up{namespace=\"$_m21_e35_ns\",service=~\"mediagenda.*\"}"
    check_cmd "$_m21_e35_ns : aucune cible de MédiAgenda en échec (up == 0)" \
      _m21x_vide "up{namespace=\"$_m21_e35_ns\",service=~\"mediagenda.*\"} == 0"
  done
  if kube get namespace mediagenda-prod >/dev/null 2>&1; then
    check_cmd "mediagenda-prod : cibles de MédiAgenda présentes et en marche" \
      bash -c '[[ "$1" -gt 0 && "$2" -eq 0 ]]' _ \
      "$(_m21x_nb 'up{namespace="mediagenda-prod",service=~"mediagenda.*"}')" \
      "$(_m21x_nb 'up{namespace="mediagenda-prod",service=~"mediagenda.*"} == 0')"
  fi
  check_cmd "cibles node_exporter des VMs (job vms) présentes" _m21x_non_vide 'up{job="vms"}'
  check_cmd "aucune cible node_exporter (VMs et nœuds Kubernetes) en échec" \
    _m21x_vide 'up{job=~"vms|node-exporter"} == 0'
  check_cmd "une alerte surveille les cibles en échec (up == 0)" _m21x_regle_qui 'up[{ ].*==[[:space:]]*0'
  check_cmd "une alerte surveille les cibles disparues (absent / absent_over_time sur up)" _m21x_regle_qui 'absent(_over_time)?\(up'
fi

check_cmd "aucune CiliumNetworkPolicy des espaces mediagenda-* ne refuse le trafic de supervision" \
  _m21x_kq '[.items[] | select(.metadata.namespace | startswith("mediagenda-"))
             | select([.spec.ingressDeny[]?.fromEndpoints[]?.matchLabels // {} | to_entries[]
                       | select(.key | test("namespace")) | .value] | index("supervision"))] | length == 0' \
  ciliumnetworkpolicies.cilium.io -A
_m21_e35_sm_retenu() {
  local sel
  sel="$(kube -n supervision get prometheuses.monitoring.coreos.com -o json 2>/dev/null | jq -c '.items[0].spec.serviceMonitorSelector.matchLabels // {}')"
  [[ -n "$sel" ]] || return 1
  kube -n mediagenda-dev get servicemonitors.monitoring.coreos.com -o json 2>/dev/null |
    jq -e --argjson s "$sel" '[.items[] | select(.metadata.name | startswith("mediagenda"))
                               | (.metadata.labels // {}) as $l | $s | to_entries | all($l[.key] == .value)] | any' >/dev/null
}
check_cmd "ServiceMonitor de MédiAgenda (mediagenda-dev) retenu par le sélecteur de Prometheus" _m21_e35_sm_retenu
check_cmd "RB-217 : section « cible disparue ou muette »" \
  _m21x_doc_contient "$_m21x_rb/RB-217-*.md" '^#+ .*(cible|collecte)'
check_cmd "panne M21-E35 close (lab/bin/break 21 35 --annuler après réparation)" _m21x_aucune_panne_active E35
