# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et PromQL entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E21.sh — M27-E21 « Panne : la migration bloque la mise en production » : Job de migration réussi,
# Application de recette synchronisée, plus de transaction oisive ni d'attente de verrou, transactions
# oisives bornées dans le Cluster ; RB-278 ; panne close. Lecture seule.

# shellcheck source=_m27-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m27-expert.sh"

title "M27-E21 — La migration ne bloque plus"
require_cmd kubectl jq curl

_M27_E21_APP="${WB_M27_APP_AGENDA:-mediagenda-recette}"
check_cmd "dernier Job mediagenda-migrations de recette réussi" \
  _m27p_kq '(.status.succeeded // 0) >= 1' -n "$_m27p_recette" jobs.batch mediagenda-migrations
check_cmd "Application $_M27_E21_APP Synced/Healthy, dernière opération réussie" \
  _m27p_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"
            and (.status.operationState.phase // "") == "Succeeded"' -n argocd applications.argoproj.io "$_M27_E21_APP"
check_cmd "aucune transaction oisive de plus de 5 min dans la base de recette" \
  _m27p_prom_nul_ou_absent "max(cnpg_backends_max_tx_duration_seconds{namespace=\"$_m27p_recette\", state=~\"idle in transaction.*\"}) > 300"
check_cmd "aucune session en attente de verrou dans la base de recette" \
  _m27p_prom_nul_ou_absent "max(cnpg_backends_waiting_total{namespace=\"$_m27p_recette\"})"
check_cmd "idle_in_transaction_session_timeout posé sur mediagenda-db (recette)" \
  _m27p_kq '(.spec.postgresql.parameters.idle_in_transaction_session_timeout // "0") | test("^0+[a-z]*$") | not' \
  -n "$_m27p_recette" clusters.postgresql.cnpg.io mediagenda-db
check_cmd "runbook RB-278 « La migration bloque la synchronisation » (verrou, repair, somme de contrôle)" \
  _m27p_doc "$_m27p_runbooks" RB-278 'pg_blocking_pids|pg_locks' 'repair' 'checksum|somme de contr' 'flyway_schema_history'
check_cmd "journal de diagnostic INC-5421" _m27x_journal_inc 5421 'hypoth' 'cause'
check_cmd "panne M27-E21 close (lab/bin/break 27 21 --annuler après réparation)" _m27p_aucune_panne_active E21
