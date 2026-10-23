# RB-275 — Reprendre MédiAgenda sur le réplica de secours

| | |
|---|---|
| Quand | La base de production `mediagenda-prod/mediagenda-db` est **perdue** (toutes les instances et leurs volumes inutilisables, corruption, erreur humaine irréparable) et ne peut pas être rétablie par une bascule CNPG (RB-270) ni par une restauration à un instant donné plus rapide (RB-162) |
| Qui décide | Claire Morel (ou son suppléant d'astreinte), sur proposition de l'astreinte, **par écrit** dans le ticket d'incident : la promotion est **irréversible** |
| Réplica | `mediagenda-secours/mediagenda-db-secours` (`plateforme/k8s/espaces/mediagenda-secours/`), alimenté par l'archive des WAL de la prod (`s3://cnpg-k8s-par1/mediagenda-db-prod/`) |
| RPO mesuré | 4 min 50 s en régime normal (≈ `archive_timeout` de 5 min) ; 25 s si un `pg_switch_wal()` a pu être fait sur la prod juste avant (essai du <AAAA-MM-JJ>, `wb-essais/secours-essai`) |
| RTO mesuré | 9 min de la décision à la première écriture de MédiAgenda sur la base promue (promotion 1 min, *pooler* et identités 6 min, vérifications 2 min) |

> Les durées sont celles du lab de référence : reporte les tiennes.

## 0. Avant de décider

1. La prod est-elle vraiment perdue ? `kubectl cnpg status mediagenda-db -n mediagenda-prod`, état des PVC et de Ceph (`ceph -s`). Une instance saine = RB-270, pas ce runbook.
2. Que vaut le secours ? `kubectl cnpg status mediagenda-db-secours -n mediagenda-secours` et, sur son instance désignée :
   ```
   SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp(), now() - pg_last_xact_replay_timestamp() AS retard;
   ```
3. Si la prod répond encore un peu (primaire vivant mais condamné) : `SELECT pg_switch_wal();` puis attendre que l'archive du segment soit faite (`pg_stat_archiver.last_archived_wal`) : c'est autant de transactions sauvées.
4. Écrire au ticket : heure de la dernière transaction rejouée = **ce que l'on perd** au-delà (à annoncer aux centres de santé : rendez-vous pris après cette heure à vérifier).

## 1. Couper l'ancienne prod

L'ancienne prod ne doit plus **jamais** écrire (deux primaires = deux historiques) : mettre à zéro l'API de production (Rollout), isoler l'ancien cluster (`kubectl cnpg fencing on mediagenda-db "*" -n mediagenda-prod`) s'il existe encore, ne rien supprimer (enquête).

## 2. Promouvoir

```
admin@adm01:~/src/k8s$ kubectl -n mediagenda-secours patch cluster mediagenda-db-secours --type merge -p '{"spec":{"replica":{"enabled":false}}}'
```
puis la même modification dans `espaces/mediagenda-secours/50-mediagenda-db-secours.yaml` (MR), avec dans la même MR :
- `.spec.plugins` : archivage sous un **nouveau** `serverName` (`mediagenda-db-secours`), jamais celui de l'ancienne prod (le plugin refuse une archive non vide ; et l'ancien historique doit rester intact) ;
- rôles gérés `mediagenda_api` et `openbao` (repris de la prod), puis le SQL de préparation d'OpenBao (M25-E14) ;
- sortie et entrée réseau : MédiAgenda → 5432 (le *pooler*), OpenBao → Service LoadBalancer de la base.

Attendre `Cluster in healthy state` (sortie de récupération, nouvelle *timeline*), puis une **sauvegarde de base immédiate** (`kubectl cnpg backup mediagenda-db-secours -n mediagenda-secours`) et un `ScheduledBackup`.

## 3. Rebrancher MédiAgenda

- `spec.cluster` d'un `Pooler` est **immuable** : créer un nouveau `Pooler` qui vise `mediagenda-db-secours` (dans `mediagenda-secours`), ou repointer l'application par une MR de `mediagenda/deploiement` (variable de connexion).
- OpenBao : nouvelle connexion du moteur `db-mediagenda` vers la base promue (`plateforme/secrets`), rôles `mediagenda-api-prod` et `mediagenda-migrateur-prod` repointés, ExternalSecret de la prod rafraîchi.
- Remettre l'API de production en service, vérifier `/pret`, une création de rendez-vous, les journaux.

## 4. Messagerie (si la grappe RabbitMQ est perdue aussi)

Les définitions sont dans `s3://messagerie-definitions/<AAAA>/<MM>/` (export nocturne, sans empreintes de mots de passe). Sur une grappe neuve : le Topology Operator recrée vhosts, utilisateurs, permissions, files et politiques depuis Git ; le fichier exporté sert à **vérifier** ou à compléter ce qui n'est pas dans Git (`POST /api/definitions/<vhost>`, par vhost). Les messages en vol au moment de la perte sont perdus : MédiAgenda ne republie pas (voir l'*outbox*, ADR-0270).

## Retour arrière

Il n'y en a pas : une fois promue, la copie est une base indépendante, l'ancienne prod a divergé (ou n'existe plus). « Revenir » sur l'ancienne prod reconstruite, ce serait une nouvelle migration de données, planifiée, pas un geste d'astreinte.

## Le secours décroche (alerte PostgresqlSecoursEnRetard)

0. Rappel : `now() - pg_last_xact_replay_timestamp()` (et `cnpg_pg_replication_lag` du secours) est l'âge de la dernière transaction **rejouée** ; il grandit aussi quand la prod n'écrit rien. L'alerte ne sonne que si la prod a archivé des WAL plus récents que ce que le secours a rejoué : c'est bien la lecture de l'archive qui est en cause.
1. La prod archive-t-elle ? `kubectl -n mediagenda-prod get cluster mediagenda-db -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}'`.
2. Le secours lit-il ? Journaux du pod (`kubectl -n mediagenda-secours logs mediagenda-db-secours-1 -c postgres | grep -i restore`), identité S3 (expirée, révoquée), flux vers `s3-01`.
3. Un trou dans l'archive (segment manquant) ne se rattrape pas : reconstruire le secours depuis la dernière sauvegarde de base (supprimer et réappliquer le `Cluster` du secours — c'est une copie, pas la prod).
