# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E14.sh — M27-E14 « Superviser les données et la messagerie » : séries collectées (RabbitMQ par
# file, alarmes, pooler, Valkey), huit familles d'alertes avec runbook, test des règles en CI, tableau
# m27-donnees provisionné, RB-274. Lecture seule.

# shellcheck source=_m27-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-production.sh"

title "M27-E14 — Supervision des données et de la messagerie"
require_cmd kubectl jq curl

for _m27_e14_v in "$_m27p_vhost_recette" "$_m27p_vhost_prod"; do
  check_cmd "RabbitMQ : messages prêts par file collectés pour le vhost $_m27_e14_v (/metrics/detailed)" \
    _m27p_prom_present "rabbitmq_detailed_queue_messages_ready{vhost=\"$_m27_e14_v\", queue=\"notifications\"}"
done
check_cmd "RabbitMQ : consommateurs par file collectés (famille queue_consumer_count)" \
  _m27p_prom_present 'rabbitmq_detailed_queue_consumers{queue="notifications"}'
check_cmd "RabbitMQ : alarmes collectées sur les trois nœuds" \
  _m27p_prom_positif 'count(rabbitmq_alarms_memory_used_watermark) >= 3'
check_cmd "RabbitMQ : pas de métriques par objet sur /metrics (per-object : cardinalité)" \
  _m27p_prom_nul_ou_absent 'count(rabbitmq_queue_messages_ready{queue!=""})'
for _m27_e14_ns in "$_m27p_recette" "$_m27p_prod"; do
  check_cmd "PgBouncer ($_m27_e14_ns) : cnpg_pgbouncer_pools_cl_waiting collecté" \
    _m27p_prom_present "cnpg_pgbouncer_pools_cl_waiting{namespace=\"$_m27_e14_ns\"}"
done
check_cmd "Valkey : exportateur collecté (redis_up) en recette ou en prod" \
  _m27p_prom_present 'redis_up{namespace=~"mediagenda-(recette|prod)"}'

check_cmd "alerte « réplication en retard » (avec runbook)" _m27p_alerte_famille 'cnpg_pg_replication_lag|replay_lag'
check_cmd "alerte « primaire absent » (avec runbook)" _m27p_alerte_famille 'cnpg_pg_replication_in_recovery'
check_cmd "alerte « réplication synchrone sans réplica » (avec runbook)" _m27p_alerte_famille 'cnpg_pg_replication_streaming_replicas'
check_cmd "alerte « clients du pooler en attente » (avec runbook)" _m27p_alerte_famille 'cnpg_pgbouncer_pools_(cl_waiting|maxwait)'
check_cmd "alerte « file qui grossit » (avec runbook)" _m27p_alerte_famille 'queue_messages(_ready)?\{'
check_cmd "alerte « file sans consommateur » (avec runbook)" _m27p_alerte_famille 'queue_consumers'
check_cmd "alerte « alarme mémoire ou disque de RabbitMQ » (avec runbook)" _m27p_alerte_famille 'rabbitmq_alarms_'
check_cmd "alerte « cache plein ou en erreur » (avec runbook)" _m27p_alerte_famille 'redis_memory_used_bytes|redis_evicted_keys|mediagenda_cache_total'
check_cmd "règles testées en CI : un fichier de tests promtool sous regles/ de plateforme/observabilite" \
  _m27p_depot_contient_tout plateforme/observabilite regles 'rule_files' 'alert_rule_test' 'rabbitmq|cnpg'

_m27_e14_tableau() {
  grafana_api "dashboards/uid/m27-donnees" 2>/dev/null | jq -e '(.dashboard | tostring) as $d
    | ($d | test("cnpg_pgbouncer")) and ($d | test("rabbitmq_detailed_queue")) and ($d | test("rabbitmq_alarms"))
      and ($d | test("redis_|mediagenda_cache")) and ($d | test("cnpg_pg_replication"))' >/dev/null 2>&1
}
check_cmd "tableau « Données et messagerie » (UID m27-donnees) : PostgreSQL, pooler, RabbitMQ, alarmes, cache" _m27_e14_tableau
check_cmd "tableau versionné dans plateforme/observabilite/tableaux/" \
  _m27p_depot_contient plateforme/observabilite tableaux '"uid": *"m27-donnees"'
check_cmd "RB-274 publié (une section par alerte, délais mesurés)" \
  _m27p_doc "$_m27p_runbooks" RB-274 'alarme' 'consommateur' 'primaire' 'pooler|PgBouncer' '[0-9]+ ?(min|s)\b'
