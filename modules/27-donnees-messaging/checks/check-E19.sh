# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E19.sh — M27-E19 « Panne : les écritures de MédiAgenda sont bloquées » : la base de recette est saine,
# aucune instance isolée, un réplica en réplication, le pooler a une réserve raisonnable sans clients en
# attente, le témoin crée des rendez-vous ; RB-276 ; panne close. Lecture seule.

# shellcheck source=_m27-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-expert.sh"

title "M27-E19 — Les écritures de MédiAgenda passent à nouveau"
require_cmd kubectl jq curl

check_cmd "mediagenda-db (recette) : instances prêtes, état sain" _m27p_cluster_sain "$_m27p_recette" mediagenda-db
check_cmd "mediagenda-db (recette) : aucune instance isolée (cnpg.io/fencedInstances)" \
  _m27p_kq '(.metadata.annotations["cnpg.io/fencedInstances"] // "[]") | (. == "" or . == "[]")' \
  -n "$_m27p_recette" clusters.postgresql.cnpg.io mediagenda-db
check_cmd "le primaire de recette a au moins un réplica en réplication (dataDurability: required)" \
  _m27p_prom_positif "max(cnpg_pg_replication_streaming_replicas{namespace=\"$_m27p_recette\"} and on (namespace, pod) cnpg_pg_replication_in_recovery == 0) >= bool 1"
check_cmd "pooler de recette : réserve et clients raisonnables (default_pool_size ≥ 5, max_client_conn ≥ 50, ou défauts)" \
  _m27p_kq '(.spec.pgbouncer.parameters // {}) as $p
    | (($p.default_pool_size // "20") | tonumber >= 5) and (($p.max_client_conn // "100") | tonumber >= 50)' \
  -n "$_m27p_recette" poolers.postgresql.cnpg.io mediagenda-db-pooler-rw
check_cmd "pooler de recette : aucun client en attente d'une connexion serveur" \
  _m27p_prom_nul_ou_absent "sum(cnpg_pgbouncer_pools_cl_waiting{namespace=\"$_m27p_recette\"})"
check_cmd "témoin de trafic présent (wb-pannes/trafic-recette)" _m27x_temoin
check_cmd "créations de rendez-vous réussies (201) en recette dans les 10 dernières minutes" _m27x_creations_recentes 10m
check_cmd "runbook RB-276 « Écritures bloquées » publié (attente ou refus)" \
  _m27p_doc "$_m27p_runbooks" RB-276 'SyncRep|synchron' 'fenc|isol' 'pooler|PgBouncer' 'permission|droit|GRANT'
check_cmd "journal de diagnostic INC-5419" _m27x_journal_inc 5419 'hypoth' 'cause'
check_cmd "panne M27-E19 close (lab/bin/break 27 19 --annuler après réparation)" _m27p_aucune_panne_active E19
