# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-E24.sh — M27-E24 « Sous le capot » : le document montre les mécanismes, sorties à l'appui, et les
# essais sont nettoyés. Lecture seule.

# shellcheck source=_m27-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-expert.sh"

title "M27-E24 — Réplication synchrone, WAL et Raft"
require_cmd kubectl jq curl

check_cmd "sous-le-capot.md : LSN relevés et pg_stat_replication" \
  _m27p_doc "$_m27p_docs" sous-le-capot '[0-9A-F]+/[0-9A-F]{6,}' 'pg_stat_replication' 'flush_lsn|replay_lsn' 'pg_waldump'
check_cmd "sous-le-capot.md : synchronous_standby_names généré par CNPG expliqué" \
  _m27p_doc "$_m27p_docs" sous-le-capot 'synchronous_standby_names' 'ANY [0-9]' 'synchronous_commit'
check_cmd "sous-le-capot.md : élection du primaire (Lease, sondes, promotion)" \
  _m27p_doc "$_m27p_docs" sous-le-capot 'Lease' 'isolation|isolement' 'promot'
check_cmd "sous-le-capot.md : Raft des files quorum (quorum_status avant et après élection, terme, journal Ra)" \
  _m27p_doc "$_m27p_docs" sous-le-capot 'quorum_status' '[Tt]erm' 'leader' 'WAL|wal' 'segment'
check_cmd "sous-le-capot.md : Khepri situé" _m27p_doc "$_m27p_docs" sous-le-capot 'Khepri'
check_cmd "wb-essais : grappe RabbitMQ d'essai retirée" _m27p_absent rabbitmqclusters.rabbitmq.com wb-essais
check_cmd "mediagenda-db (recette) saine après la bascule demandée" _m27p_cluster_sain "$_m27p_recette" mediagenda-db
