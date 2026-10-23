# INC-5419 — Écritures bloquées en recette (journal de diagnostic, exemple : variante 1)

| Heure | Hypothèse | Commande | Résultat | Conclusion |
|---|---|---|---|---|
| 09:02 | L'API échoue sur les écritures seulement | journaux de l'API, `mediagenda_http_requests_total` par code | `POST` → 500 après 30 s (`canceling statement due to user request`, délai du client), `GET` 200 | attente côté base, pas refus |
| 09:05 | Le pooler sature | tableau `m27-donnees`, `cnpg_pgbouncer_pools_cl_waiting` | 12 clients en attente, 20 connexions serveur toutes « actives » | le pooler attend la base : symptôme, pas cause |
| 09:07 | Les sessions attendent un verrou ou la réplication | `SELECT wait_event_type, wait_event, count(*) FROM pg_stat_activity WHERE datname='mediagenda' GROUP BY 1,2;` | 20 × `IPC`/`SyncRep` | attente de la réplication synchrone |
| 09:08 | Plus aucun réplica | `SELECT * FROM pg_stat_replication;` ; `SHOW synchronous_standby_names;` | 0 ligne ; `ANY 1 ("mediagenda-db-1","mediagenda-db-3","mediagenda-db-2")` | aucun réplica connecté, `required` |
| 09:10 | Réplicas arrêtés ou isolés | `kubectl cnpg status` ; annotations du `Cluster` | `cnpg.io/fencedInstances: ["mediagenda-db-1","mediagenda-db-3"]` | **cause** : deux réplicas isolés |
| 09:12 | Qui ? | audit Kubernetes (Loki, locataire `audit`) : `patch` du Cluster | annotation posée par une session d'administration à 22 h 40 la veille | geste manuel, pas dans Git |
| 09:14 | Correctif | `kubectl cnpg fencing off mediagenda-db "*" -n mediagenda-recette` (l'annotation n'est pas dans Git) | réplicas `streaming` en 40 s, 12 validations en attente terminées | rétabli ; aucune transaction perdue |
