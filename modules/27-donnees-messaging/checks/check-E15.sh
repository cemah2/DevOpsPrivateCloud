# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E15.sh — M27-E15 « Reprise et montée de version » : réplica de secours autonome, sain, sans archivage
# propre, à jour et surveillé ; aucune copie d'essai restante ; export nocturne des définitions réussi ;
# grappe en 4.3 ou en 4.4 avec la décision écrite ; RB-275. Lecture seule.

# shellcheck source=_m27-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-production.sh"

title "M27-E15 — Réplica de secours et montée de RabbitMQ"
require_cmd kubectl jq curl

check_cmd "mediagenda-db-secours : réplica autonome (replica.enabled) alimenté par le plugin Barman Cloud" \
  _m27p_kq '.spec.replica.enabled == true
            and any(.spec.externalClusters[]?; (.plugin.name // "") == "barman-cloud.cloudnative-pg.io" and (.plugin.parameters.serverName // "") != "")' \
  -n "$_m27p_secours" clusters.postgresql.cnpg.io mediagenda-db-secours
check_cmd "mediagenda-db-secours : n'archive rien lui-même (aucun plugin isWALArchiver)" \
  _m27p_kq '[.spec.plugins[]? | select(.isWALArchiver == true)] | length == 0' \
  -n "$_m27p_secours" clusters.postgresql.cnpg.io mediagenda-db-secours
check_cmd "mediagenda-db-secours : instances prêtes, état sain" _m27p_cluster_sain "$_m27p_secours" mediagenda-db-secours
check_cmd "mediagenda-db-secours : la source n'est pas l'archive de la recette (serverName ≠ mediagenda-db)" \
  _m27p_kq '[.spec.externalClusters[]?.plugin.parameters.serverName // empty] | length > 0 and all(. != "mediagenda-db")' \
  -n "$_m27p_secours" clusters.postgresql.cnpg.io mediagenda-db-secours
if _m27p_peut get objectstores.barmancloud.cnpg.io "$_m27p_secours"; then
  check_cmd "ObjectStore du secours sans politique de rétention (il ne doit rien effacer)" \
    _m27p_kq '[.items[] | select(.spec.retentionPolicy != null)] | length == 0' -n "$_m27p_secours" objectstores.barmancloud.cnpg.io
else
  skip "ObjectStore du secours sans politique de rétention" "objectstores.barmancloud.cnpg.io non lisible par wb-checks"
fi
# Retard mesuré par rapport à l'ARCHIVE de la prod : sur un réplica nourri par l'archive, le lag CNPG est
# l'âge de la dernière transaction rejouée et grandit quand la prod n'écrit rien. On exige que la prod n'ait
# rien archivé plus de 15 min après la dernière transaction rejouée par le secours (prod au repos : OK).
check_cmd "réplica de secours collecté et en retard de moins de 15 min sur l'archive de la prod" \
  _m27p_prom_positif "(max(cnpg_pg_stat_archiver_last_archived_time{namespace=\"$_m27p_prod\"}) - on () (time() - max(cnpg_pg_replication_lag{namespace=\"$_m27p_secours\"}))) < bool 900"
check_cmd "une alerte surveille le retard du réplica de secours" _m27p_alerte_famille "$_m27p_secours"

check_cmd "wb-essais : aucun Cluster CNPG d'essai restant (copie de production)" _m27p_absent clusters.postgresql.cnpg.io wb-essais
check_cmd "wb-essais : aucune grappe RabbitMQ d'essai restante" _m27p_absent rabbitmqclusters.rabbitmq.com wb-essais
# Les PVC d'un RabbitmqCluster supprimé RESTENT (StatefulSet) : ceux de l'essai contiennent des messages.
_m27_e15_pvc() {
  _m27p_cluster_joignable || return 1
  kube get namespace wb-essais >/dev/null 2>&1 || return 0
  _m27p_kq '[.items[] | select(.metadata.name | test("rabbitmq-essai|secours-essai"))] | length == 0' -n wb-essais persistentvolumeclaims
}
check_cmd "wb-essais : aucun volume restant des essais (rabbitmq-essai, secours-essai)" _m27_e15_pvc

_m27_e15_export() {
  kube -n messagerie get cronjob export-definitions -o json 2>/dev/null |
    jq -e '(.status.lastSuccessfulTime // "1970-01-01T00:00:00Z") | fromdateiso8601 > (now - 26*3600)' >/dev/null 2>&1
}
check_cmd "CronJob messagerie/export-definitions réussi dans les dernières 26 h" _m27_e15_export

_M27_E15_VERSION="$(rabbitmq_api overview 2>/dev/null | jq -r '.rabbitmq_version // empty' 2>/dev/null)" || _M27_E15_VERSION=""
_m27_e15_version() { [[ "$_M27_E15_VERSION" =~ ^4\.(3|4)\. ]]; }
check_cmd "messagerie/rabbitmq en 4.3.x ou 4.4.x (version lue : ${_M27_E15_VERSION:-illisible})" _m27_e15_version
_m27_e15_decision() {
  local mm="${_M27_E15_VERSION%.*}"
  [[ -n "$mm" ]] || return 1
  _m27p_doc "$_m27p_docs" montee-rabbitmq 'r[ée]p[ée]tition|wb-essais' 'feature.?flag' "${mm//./\\.}" 'd[ée]cision'
}
check_cmd "montee-rabbitmq-4.4.md : répétition, feature flags et décision cohérente avec la version en service" _m27_e15_decision
check_cmd "RB-275 publié : reprise sur le secours, RPO et RTO mesurés" \
  _m27p_doc "$_m27p_runbooks" RB-275 'RPO' 'RTO' 'promo' 'serverName' '[0-9]+ ?(min|s)\b'
