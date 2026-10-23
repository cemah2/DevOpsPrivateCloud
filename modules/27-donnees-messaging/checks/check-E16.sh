# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E16.sh — M27-E16 « Performance et dimensionnement » : mesures et recommandation écrites, manifestes
# du banc versionnés, banc retiré de wb-essais. Lecture seule.

# shellcheck source=_m27-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-production.sh"

title "M27-E16 — Performance et dimensionnement"
require_cmd kubectl jq curl

check_cmd "dimensionnement.md : mesures pgbench en direct et par le pooler, avec et sans -C" \
  _m27p_doc "$_m27p_docs" dimensionnement 'pgbench' 'pooler' '(-C|--connect)' 'TPS|tps' 'latence'
check_cmd "dimensionnement.md : mesures perf-test (confirmations, prefetch, file quorum)" \
  _m27p_doc "$_m27p_docs" dimensionnement 'perf-test' 'confirm' 'prefetch' 'quorum' 'msg/s|messages par seconde'
check_cmd "dimensionnement.md : recommandation chiffrée pour janvier (réserve, connexions, consommateurs)" \
  _m27p_doc "$_m27p_docs" dimensionnement 'janvier' 'default_pool_size' 'max_connections' 'r[ée]plicas?'
check_cmd "plateforme/donnees : manifestes du banc dans outils/banc/ (Pooler et pgbench)" \
  _m27p_depot_contient_tout plateforme/donnees outils/banc 'kind: *Pooler' 'poolMode: *transaction'
check_cmd "plateforme/donnees : Job ou manifeste perf-test dans outils/banc/" \
  _m27p_depot_contient plateforme/donnees outils/banc 'perf-test'
check_cmd "wb-essais : banc PostgreSQL retiré (aucun Cluster CNPG)" _m27p_absent clusters.postgresql.cnpg.io wb-essais
check_cmd "wb-essais : banc PostgreSQL retiré (aucun Pooler)" _m27p_absent poolers.postgresql.cnpg.io wb-essais
check_cmd "wb-essais : grappe RabbitMQ de banc retirée" _m27p_absent rabbitmqclusters.rabbitmq.com wb-essais
_m27_e16_jobs() {
  _m27p_kq '[.items[] | select(.metadata.name | test("pgbench|perf-test"))] | length == 0' -n wb-essais jobs.batch
}
check_cmd "wb-essais : aucun Job pgbench ou perf-test restant" _m27_e16_jobs
