# RB-276 — Écritures bloquées sur une base CloudNativePG

| | |
|---|---|
| Symptôme | Les créations ou modifications échouent ou attendent ; les lectures passent (au moins en partie) |
| Alertes associées | `PostgresqlSynchroneSansReplica`, `PgbouncerClientsEnAttente`, `PostgresqlInstanceIsolee` (RB-274) ; taux d'erreurs de MédiAgenda (RB-211) |
| Base | `mediagenda-db` (recette ou prod), pooler `mediagenda-db-pooler-rw` |

## 1. Attend ou refuse ?

Journaux de l'API sur une requête d'écriture :
- **délai dépassé** (`canceling statement`, `timeout`, la requête dure le délai du client) → l'écriture **attend** : section 2 ;
- **erreur immédiate** (`permission denied for table …`, `no more connections allowed`, `violates … constraint`) → l'écriture est **refusée** : section 3.

## 2. L'écriture attend

Sur le primaire (`kubectl cnpg psql mediagenda-db -n <ESPACE> -- -d mediagenda`) :

```sql
SELECT wait_event_type, wait_event, state, count(*) FROM pg_stat_activity WHERE datname = 'mediagenda' GROUP BY 1, 2, 3 ORDER BY 4 DESC;
```

| Attente | Preuve | Cause probable | Geste |
|---|---|---|---|
| `IPC` / `SyncRep` | `pg_stat_replication` vide ou sans `sync_state` `quorum`/`sync` ; `SHOW synchronous_standby_names;` non vide | aucun réplica connecté avec `dataDurability: required` : réplicas isolés (`cnpg.io/fencedInstances`), arrêtés, en reclonage, nœuds drainés | rétablir un réplica (lever l'isolement : `kubectl cnpg fencing off …`, puis retirer l'annotation de Git si elle y est) ; **ne pas** passer en `preferred` dans l'urgence (décision d'architecture, ADR-0270) |
| `Lock` | `SELECT pid, pg_blocking_pids(pid), wait_event, left(query,60) FROM pg_stat_activity WHERE wait_event_type = 'Lock';` puis la session bloquante (`state`, `xact_start`) | une transaction longue ou oisive qui tient un verrou (migration, session oubliée) | identifier, prévenir son propriétaire, `SELECT pg_terminate_backend(<pid>);` en le notant ; prévention : `idle_in_transaction_session_timeout`, `lock_timeout` (RB-278) |
| rien côté PostgreSQL, mais le client attend | pooler : `cnpg_pgbouncer_pools_cl_waiting` > 0, `maxwait` qui monte, peu de connexions serveur | réserve du pooler trop petite (`default_pool_size`), ou connexions serveur tenues par des transactions longues | corriger le `Pooler` **là où il est déclaré** (Git) ; les paramètres sont rechargés sans coupure ; dimensionnement : `docs/donnees/dimensionnement.md` |

## 3. L'écriture est refusée

| Message | Preuve | Geste |
|---|---|---|
| `permission denied for table rendez_vous` | `SELECT has_table_privilege('mediagenda_api', 'public.rendez_vous', 'INSERT');` → `f` ; `\dp rendez_vous` | rendre les droits du rôle de groupe (`GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mediagenda_api;`, script de préparation du M25-E14) ; retrouver le script ou le geste en cause (Git de `plateforme/k8s`, `log_statement` si actif) et le retirer |
| `no more connections allowed (max_client_conn)` | `SHOW CONFIG;` du pooler, métriques | relever `max_client_conn` dans le `Pooler` (Git) |
| `too many connections for role/database` | `pg_roles.rolconnlimit`, `pg_database.datconnlimit` | corriger la limite (rôle géré, CRD `Database`) |
| `cannot execute INSERT in a read-only transaction` | l'API vise un réplica | le Service ou le pooler vise `-ro` au lieu de `-rw` : corriger la cible |

## 4. Après

Une création de rendez-vous de bout en bout en moins d'une seconde ; `pg_stat_replication` avec au moins un réplica en `quorum` ; journal d'incident et, si un geste manuel était en cause, une action pour qu'il passe désormais par Git.
