# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E19.sh — M23-E19 « Panne : plus aucune trace » : la chaîne application → agent → passerelle → Tempo
# fonctionne de bout en bout, rien ne bloque l'OTLP, le runbook est écrit, la panne est close. Lecture seule.

# shellcheck source=_m23-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-expert.sh"

title "M23-E19 — Les traces arrivent à nouveau"
require_cmd kubectl jq curl

check_cmd "otel-agent (DaemonSet) prêt sur tous ses nœuds" _m23p_collector_pret "$_m23p_agent"
check_cmd "otel-passerelle prête" _m23p_collector_pret "$_m23p_passerelle"
check_cmd "traces récentes (10 min) de mediagenda-api en dev" _m23p_traces 600 "$_m23x_sel_agenda"
check_cmd "traces récentes (10 min) de medidoc en dev" _m23p_traces 600 "$_m23x_sel_doc"
check_cmd "espace traces : aucune règle Cilium ne refuse l'OTLP (ingressDeny sur 4317/4318)" \
  _m23p_kq '[.items[] | select(.spec.ingressDeny? != null) | .spec.ingressDeny[].toPorts[]?.ports[]?.port | select(. == "4317" or . == "4318")] | length == 0' \
  -n traces ciliumnetworkpolicies.cilium.io
check_cmd "passerelle : l'exportateur vers Tempo vise un Service qui existe (tempo.traces)" \
  _m23p_config_collector "$_m23p_passerelle" '[.exporters[] | (.endpoint? // "") | select(test("(^|/)tempo(\\.traces)?(\\.svc)?(\\.cluster\\.local)?:4317$"))] | length >= 1'
check_cmd "agent : récepteur OTLP en gRPC et en HTTP" \
  _m23p_config_collector "$_m23p_agent" '[.receivers[] | select(.protocols.grpc? != null and .protocols.http? != null)] | length >= 1'
check_cmd "aucune erreur d'export récente des collectors (otelcol_exporter_send_failed_spans, 10 min)" \
  _m23p_prom_nul_ou_absent 'sum(increase({__name__=~"otelcol_exporter_send_failed_spans(_total)?"}[10m]))'
check_cmd "runbook RB-230 « Plus aucune trace » publié" \
  _m23p_doc "$_m23x_runbooks" RB-230 'agent' 'passerelle' 'otelcol_'
check_cmd "panne M23-E19 close (lab/bin/break 23 19 --annuler après réparation)" _m23x_aucune_panne_active E19
