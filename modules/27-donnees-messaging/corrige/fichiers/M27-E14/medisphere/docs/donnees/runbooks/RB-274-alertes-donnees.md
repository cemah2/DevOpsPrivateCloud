# RB-274 — Alertes des données et de la messagerie

| | |
|---|---|
| Portée | `mediagenda-db` (recette, prod), `mediagenda-db-pooler-rw`, `messagerie/rabbitmq`, Valkey de MédiAgenda, réplica de secours |
| Règles | `plateforme/observabilite/regles/alertes-donnees.yaml` (M27-E14) |
| Tableau | Grafana « Données et messagerie » (UID `m27-donnees`) |
| Accès | `adm01` : contexte `k8s-par1` (OIDC), `kubectl cnpg`, interface RabbitMQ (OAuth), compte d'administration Valkey (OpenBao `kv/mediagenda/<env>/valkey-admin`) |

Règle commune : **observer avant d'agir**. Aucune purge de file, aucune suppression de PVC, aucun `pg_terminate_backend` sans avoir écrit dans le journal d'incident ce que fait la session.

Délais mesurés en recette (M27-E14, étape 6, lab de référence ; remplace par les tiens) : « file sans consommateur » *pending* 30 s après l'arrêt de MédiNotif, *firing* 15 min 30 s plus tard (recette) ; « instance isolée » *firing* 5 min 40 s après `fencing on`.

## PostgresqlReplicationEnRetard

- **Sens** : un réplica rejoue avec plus de 30 s de retard depuis 5 min.
- **D'abord** : `kubectl cnpg status mediagenda-db -n <ESPACE>` (section *Streaming Replication status*), puis sur le primaire `SELECT application_name, state, sync_state, write_lag, flush_lag, replay_lag FROM pg_stat_replication;`.
- **Causes** : nœud ou volume Ceph lent (`kubectl top`, tableau Ceph du M21), grosse opération (index, `VACUUM FULL`, chargement), requête longue sur le réplica qui bloque le rejeu (`max_standby_streaming_delay`), réseau.
- **Geste** : traiter la cause. Si le réplica ne rattrape jamais, le reconstruire (`kubectl cnpg destroy mediagenda-db <N> -n <ESPACE>` supprime l'instance **et son PVC**) est une décision, pas un geste d'astreinte : RB-270, et escalader.

## PostgresqlPrimaireAbsent

- **Sens** : aucune instance n'est à la fois joignable et primaire depuis 1 min (ou plus aucune instance de prod n'est collectée).
- **D'abord** : `kubectl cnpg status` (phase : *Failing over* ?), `kubectl -n <ESPACE> get pods -l cnpg.io/cluster=mediagenda-db -o wide`, `kubectl -n <ESPACE> get lease mediagenda-db`, journaux de l'opérateur (`kubectl -n cnpg-system logs deploy/cnpg-controller-manager --since=10m`).
- **Causes** : bascule en cours (normal pendant moins d'une minute), toutes les instances isolées, nœuds indisponibles, quota, PVC non montable.
- **Geste** : laisser la bascule finir ; si elle ne finit pas en 2 min, RB-270 (bascule manuelle `kubectl cnpg promote`). Si plus rien ne démarre : RB-275 (reprise sur le secours) — décision de Claire.

## PostgresqlSynchroneSansReplica

- **Sens** : le primaire n'a plus aucun réplica connecté ; avec `dataDurability: required`, **toutes les écritures attendent**.
- **D'abord** : `SHOW synchronous_standby_names;` et `pg_stat_replication` sur le primaire ; annotations du `Cluster` (`cnpg.io/fencedInstances`) ; état des pods réplicas.
- **Causes** : réplicas isolés (fencing), arrêtés, sur des nœuds drainés, en reclonage.
- **Geste** : rétablir un réplica (lever l'isolement par le code, ou attendre le reclonage). Ne **pas** passer en `preferred` sous la pression : c'est accepter de perdre des validations (ADR-0270). Voir RB-276.

## PostgresqlInstanceIsolee

- **Sens** : une instance est isolée (`cnpg.io/fencedInstances`) depuis 5 min.
- **D'abord** : `kubectl -n <ESPACE> get cluster mediagenda-db -o jsonpath='{.metadata.annotations.cnpg\.io/fencedInstances}'` ; qui l'a posée (journal d'audit, M22 : `{job="kubernetes-audit"} |= "fencedInstances"`).
- **Geste** : si aucune intervention n'est en cours, lever l'isolement là où il est déclaré (`kubectl cnpg fencing off` puis retirer l'annotation du dépôt si elle y est).

## PgbouncerClientsEnAttente

- **Sens** : plus de 5 clients attendent une connexion serveur depuis 2 min.
- **D'abord** : métriques `cnpg_pgbouncer_pools_*` (tableau), `SHOW POOLS;` / `SHOW CONFIG;` (console `pgbouncer` du pooler), transactions longues côté PostgreSQL (`pg_stat_activity` triée par `xact_start`).
- **Causes** : `default_pool_size` trop petit pour la charge, transactions qui tiennent leur connexion (oisives en transaction, requêtes lentes), base qui attend elle-même (voir les deux alertes précédentes).
- **Geste** : traiter la cause côté base d'abord ; ajuster la réserve dans le `Pooler` (Git) en restant sous `max_connections` (dimensionnement : `docs/donnees/dimensionnement.md`).

## RabbitmqFileQuiGrossit

- **Sens** : plus de 100 messages prêts dans `notifications` et une pente positive depuis 15 min.
- **D'abord** : consommateurs de la file et taux de livraison (interface, tableau) ; pods MédiNotif ; redélivrances.
- **Causes** : consommateurs trop peu nombreux (pic du matin), lents (passerelle SMS), bloqués sur un message (RB-277).
- **Geste** : RB-277 si les consommateurs sont absents ou bloqués ; sinon augmenter les réplicas de MédiNotif par MR (en attendant KEDA, M28).

## RabbitmqFileSansConsommateur

- **Sens** : aucun consommateur sur `notifications` (5 min en prod, critique ; 15 min en recette).
- **Geste** : RB-277.

## RabbitmqAlarmeRessource

- **Sens** : alarme mémoire ou disque sur un nœud : **tous** les publieurs de la grappe sont bloqués (prod comprise).
- **D'abord** : `kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics alarms` puis `rabbitmq-diagnostics memory_breakdown` ou `df` du volume ; files qui débordent (messages par file).
- **Causes** : une file qui s'accumule sans consommateur (mémoire, disque), un seuil mal réglé dans `additionalConfig` (`vm_memory_high_watermark.*`, `disk_free_limit.*`), un volume trop petit.
- **Geste** : faire consommer ce qui s'accumule (jamais purger sans décision), agrandir le PVC (`ceph-rbd` extensible : modifier `persistence.storage` du `RabbitmqCluster`), corriger le seuil par MR — un changement d'`additionalConfig` **redémarre** les nœuds un à un.

## ValkeyCachePlein, MediagendaCacheEnErreur, ValkeyInjoignable

- **Sens** : le cache est plein et inefficace, ou l'API n'arrive plus à le lire (mode dégradé : créneaux recalculés depuis la base).
- **Geste** : RB-279.

## PostgresqlSecoursEnRetard

- **Geste** : RB-275, section « Le secours décroche ».
