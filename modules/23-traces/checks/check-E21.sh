# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E21.sh — M23-E21 « Panne : le Collector perd des données » : plus de refus ni de pertes, réglages
# raisonnables, une alerte surveille la perte de spans. Lecture seule.

# shellcheck source=_m23-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m23-expert.sh"

title "M23-E21 — Le Collector ne perd plus de données"
require_cmd kubectl jq yq curl

check_cmd "aucun refus de spans par les récepteurs ou le memory_limiter (10 min)" \
  _m23p_prom_nul_ou_absent 'sum(increase({__name__=~"otelcol_receiver_refused_spans(_total)?|otelcol_processor_memory_limiter_refused_spans(_total)?"}[10m]))'
check_cmd "aucun échec de mise en file ni d'envoi des exportateurs (10 min)" \
  _m23p_prom_nul_ou_absent 'sum(increase({__name__=~"otelcol_exporter_enqueue_failed_spans(_total)?|otelcol_exporter_send_failed_spans(_total)?"}[10m]))'
check_cmd "files d'attente des exportateurs remplies à moins de 50 %" \
  _m23p_prom_nul_ou_absent 'max(otelcol_exporter_queue_size / otelcol_exporter_queue_capacity) > 0.5'
check_cmd "passerelle : memory_limiter dimensionné (limit_mib ≥ 200 ou limit_percentage)" \
  _m23p_config_collector "$_m23p_passerelle" '[.processors | to_entries[] | select(.key | test("^memory_limiter")) | .value
     | select((.limit_mib // 0) >= 200 or (.limit_percentage // 0) > 0)] | length >= 1'
check_cmd "passerelle : files d'attente d'au moins 100 éléments sur chaque exportateur qui en déclare une" \
  _m23p_config_collector "$_m23p_passerelle" 'all(.exporters[] | select(.sending_queue? != null); (.sending_queue.queue_size // 1000) >= 100)'
check_cmd "passerelle : lots bornés (send_batch_max_size entre 1 et 10000, ou lot de l'exportateur borné)" \
  _m23p_config_collector "$_m23p_passerelle" '([.processors | to_entries[] | select(.key | test("^batch")) | .value.send_batch_max_size // 0 | select(. > 0 and . <= 10000)] | length >= 1)
     or ([.exporters[] | .sending_queue.batch.max_size? // 0 | select(. > 0)] | length >= 1)'
check_cmd "Tempo : pas de délai artificiel, rafale d'ingestion d'au moins 4 Mo" \
  _m23p_tempo_conf_jq '.overrides.defaults.ingestion as $i | (($i.artificial_delay // "0s") | test("^0")) and (($i.burst_size_bytes // 30000000) >= 4000000)'
_m23_e21_alerte() {
  kube get prometheusrules.monitoring.coreos.com -A -o json 2>/dev/null |
    jq -e '[.items[].spec.groups[]?.rules[]? | select(.alert != null) | .expr | tostring
            | select(test("otelcol_(exporter_send_failed|exporter_enqueue_failed|receiver_refused|processor_memory_limiter_refused)"))] | length >= 1' >/dev/null 2>&1
}
check_cmd "une alerte Prometheus surveille la perte de spans des collectors" _m23_e21_alerte
check_cmd "runbook RB-237 « Le Collector perd des données » publié" \
  _m23p_doc "$_m23x_runbooks" RB-237 'memory_limiter' 'sending_queue|file' 'RATE_LIMITED|burst'
check_cmd "panne M23-E21 close (lab/bin/break 23 21 --annuler après réparation)" _m23x_aucune_panne_active E21
