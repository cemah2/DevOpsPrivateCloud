# PostgreSQL de MédiAgenda (CloudNativePG)

> `docs/donnees/postgresql.md` — M27-E02 (PLAT-2802). Fiche d'exploitation. Runbook d'astreinte :
> [RB-270](runbooks/RB-270-postgresql-maintenance-bascule.md).

## Où chaque objet est défini

| Objet | Recette (`mediagenda-recette`) | Prod (`mediagenda-prod`) |
|---|---|---|
| Cluster `mediagenda-db` (3 instances, PostgreSQL 18.6, synchrone `any 1`, `dataDurability: required`) | `plateforme/k8s` : `espaces/mediagenda-recette/50-mediagenda-db.yaml` (`task appliquer`) | `mediagenda/deploiement` : `components/dependances` + `overlays/prod/base-*.yaml` (Argo CD, synchronisation **manuelle**) |
| Rôles gérés (`managed.roles`) | `mediagenda_api`, `openbao` (M25), `mediagenda_lecture`, `lucas_lecture` (temporaire, expire le 30/10) | `mediagenda_api`, `openbao` |
| Droits sur les tables (non déclarables par CNPG) | `espaces/mediagenda-recette/sql/*.sql`, joués une fois en superutilisateur | `overlays/prod/sql/*.sql` (mêmes fichiers) |
| Base `mediagenda` (CRD `Database` `mediagenda-db-mediagenda`, `databaseReclaimPolicy: retain`) | `55-mediagenda-db-base.yaml` | `overlays/prod/pooler.yaml` |
| Pooler `mediagenda-db-pooler-rw` (PgBouncer 1.26.1, transaction, 2 pods) + PDB | `56-mediagenda-db-pooler.yaml` | `overlays/prod/pooler.yaml` |
| Supervision : PodMonitor `mediagenda-db` (9187), `mediagenda-db-pooler-rw` (9127) | `mediagenda/deploiement`, `components/supervision` | idem |
| `pg_stat_statements` (`pg_stat_statements.max: 5000`, `track: top`) | paramètres du Cluster | `overlays/prod/base-pg-stat-statements.yaml` |

## Chemin des connexions

```
API (Rollout mediagenda) ──5432──► Service mediagenda-db-pooler-rw ──► PgBouncer (2 pods, transaction)
                                                                      └─5432─► mediagenda-db-rw (primaire)
Job mediagenda-migrations (Flyway, M27-E05) ──5432──────────────────────────► mediagenda-db-rw (DIRECT)
OpenBao (vault01-03) ──5432──► mediagenda-db-openbao (LoadBalancer .64 recette / .65 prod) ─► primaire
```

- Identifiants de l'API et du migrateur : **dynamiques** (OpenBao, bail 1 h, ExternalSecret rafraîchi toutes les 30 min, M25). PgBouncer authentifie chaque compte par `auth_query` (rôle `cnpg_pooler_pgbouncer`, géré par l'opérateur) : un compte créé par OpenBao passe sans configuration.
- **Jamais par le pooler** : migrations (verrou consultatif de session de Flyway), sessions interactives d'administration (`kubectl cnpg psql` va directement à l'instance), tout ce qui utilise `SET` de session, `LISTEN`, tables temporaires.
- Instructions préparées : conservées (PgBouncer ≥ 1.22 avec `max_prepared_statements` = 200 par défaut, psycopg 3.3 avec libpq 18).

## Réglages du pooler

| Paramètre | Recette | Prod | Pourquoi |
|---|---|---|---|
| `max_client_conn` | 200 | 300 | clients PgBouncer (pods × réserve psycopg, Rollout compris) |
| `default_pool_size` | 10 | 15 | connexions serveur par couple (base, utilisateur) ; deux comptes dynamiques coexistent pendant 30 min |
| `max_db_connections` | 40 | 50 | plafond vers PostgreSQL (`max_connections` 100) : marge pour migrations, supervision, OpenBao |
| `idle_transaction_timeout` | 60 s | 60 s | une transaction oubliée ne garde pas une connexion serveur |

Lecture rapide : `kubectl cnpg pgbouncer` n'existe pas ; on lit les métriques (`cnpg_pgbouncer_pools_cl_waiting` > 0 durablement = réserve trop petite ou base lente) ou on interroge la console de PgBouncer depuis un pod du pooler :

```
admin@adm01:~$ kubectl -n mediagenda-recette exec deploy/mediagenda-db-pooler-rw -c pgbouncer -- psql -c 'SHOW POOLS;'
```

## Opérations courantes (mesurées en recette le <AAAA-MM-JJ>)

| Opération | Commande | Effet mesuré |
|---|---|---|
| Bascule planifiée | `kubectl cnpg promote mediagenda-db <instance> -n <espace>` | … s sans écriture ; clients du pooler : erreurs pendant … s, sans redémarrage de l'API |
| Nœud d'une réplique drainé | `kubectl drain <nœud> --ignore-daemonsets --delete-emptydir-data`, puis `uncordon` | aucune coupure ; l'instance attend le retour du nœud (`Pending`) |
| Nœud du primaire drainé | même commande | bascule automatique **avant** l'éviction (PDB du primaire) ; … s sans écriture |
| Nouvelle image (même mineure) | `imageName` par empreinte, MR | réplicas, puis bascule, puis ancien primaire ; … s sans écriture |

Avant toute opération en prod : `kubectl cnpg status` sain, sauvegarde `Completed` de moins d'une heure (`kubectl cnpg backup`), annonce dans le canal d'astreinte, sonde de `/pret` qui tourne.

## Requêtes les plus coûteuses

```
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -c "
  SELECT calls, round(total_exec_time) AS total_ms, round(mean_exec_time::numeric, 2) AS moy_ms,
         left(regexp_replace(query, '\s+', ' ', 'g'), 90) AS requete
    FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 5"
```

Remise à zéro (après une optimisation, pour mesurer) : `SELECT pg_stat_statements_reset();` — en superutilisateur, sur le primaire. Le texte des requêtes ne contient pas les valeurs (paramètres `$1`…) : pas de donnée de santé.

## Accès temporaires

Un accès en lecture se donne par un rôle géré **avec** `validUntil` (PostgreSQL refuse ensuite toute authentification par mot de passe), membre de `mediagenda_lecture`, mot de passe dans OpenBao (`kv/mediagenda/<env>/lecture-<personne>`). À l'échéance : `ensure: absent` (MR), puis retrait du bloc et du chemin OpenBao. Jamais en production sans ticket `SEC-` validé par Sophie Laurent.
