# Résilience des données sous charge — rapport du <DATE> (PLAT-3015)

> Exemple de rapport (lab de référence). Les chiffres sont **les tiens** : remplace-les. La forme compte : chronologie, mesures, garanties contre observations, limites.

## Résumé

| Essai | Fenêtre d'erreurs vue par l'utilisateur | Requêtes en erreur | Retour du p95 < 250 ms | Perte |
|---|---|---|---|---|
| Bascule **subie** (primaire tué, `PodChaos` `pod-kill`, `gracePeriod: 0`) | 19 s | 212 sur ≈ 5 700 (3,7 % de la minute), codes 500 (`OperationalError` de psycopg) et 503 (sonde `/pret`) | 1 min 40 | aucune transaction validée perdue (réplique synchrone) |
| Bascule **voulue** (`kubectl cnpg promote mediagenda-db mediagenda-db-2`) | 4 s | 31 (codes 500) | 25 s | aucune |
| Nœud RabbitMQ perdu (`rabbitmq-server-1` supprimé, **CHG-3015**) | 0 s côté API | 0 ; 3 publications refaites par le client (connexion sur le nœud perdu) | sans effet | aucune notification perdue, 2 doublons expliqués |

Charge : `TestRun` de M29-E14, 20 itérations/s (≈ 95 requêtes/s), palier de 10 min ; mesures dans Thanos Query (pas de 5 s) et dans k6.

## 1. Bascule subie du primaire

Chronologie (heure de Paris) :

| Heure | Fait | Preuve |
|---|---|---|
| 10:02:00 | `PodChaos` `m29-e15-pod-kill-primaire` appliqué ; `mediagenda-db-1` (primaire) tué sans délai de grâce | événement `Killed` de l'expérience, `containerRecords` |
| 10:02:01 | premières erreurs 500 : le pooler perd ses connexions serveur ; les transactions en cours échouent | `mediagenda_http_requests_total{code="500"}`, journaux Loki `mediagenda.acces` |
| 10:02:05 | sondes `/pret` en échec (base injoignable par le pooler) : les deux API sortent des points de terminaison → 503 de la Gateway | `kube_pod_status_ready`, k6 `status=503` |
| 10:02:13 | l'opérateur constate la perte, choisit `mediagenda-db-2` (réplique synchrone la plus avancée) | `kubectl cnpg status` : `Failing over`, événements du `Cluster` |
| 10:02:17 | `mediagenda-db-2` promu, Service `mediagenda-db-rw` repointé | `status.currentPrimary`, `currentPrimaryTimestamp` |
| 10:02:20 | le pooler ouvre de nouvelles connexions serveur ; dernières erreurs | journaux du pooler (`new connection to server`) |
| 10:03:40 | p95 < 250 ms (ré-échauffement du cache des créneaux et du pool) | p95 serveur |
| 10:04:30 | `mediagenda-db-1` revient en réplique (`pg_rewind`) ; réplication synchrone rétablie | `kubectl cnpg status` |

**Rôle du pooler.** En mode `transaction`, PgBouncer n'attache une connexion serveur qu'au temps d'une transaction : à la mort du primaire, seules les transactions **en cours** échouent ; les clients (MédiAgenda) gardent leur connexion au pooler et ne voient pas le changement d'adresse. Sans pooler, MédiAgenda aurait perdu **toutes** ses connexions du pool psycopg vers `mediagenda-db-rw` et dû les rouvrir (erreurs jusqu'à la reconnexion de chaque connexion, selon la politique de reconnexion du pool). Le pooler ne **rejoue** pas une transaction échouée : c'est à l'application de réessayer (elle ne le fait pas aujourd'hui → action DEV-3015).

## 2. Bascule voulue (`promote`)

`kubectl cnpg promote` : l'opérateur arrête proprement le primaire (point de reprise, WAL envoyés), promeut la cible, puis rattache l'ancien primaire en réplique. Fenêtre d'erreurs de 4 s (transactions en cours au moment de l'arrêt). C'est la procédure de toute maintenance (M27-E02) : **toujours** préférer une bascule voulue à un arrêt brutal.

## 3. Perte d'un nœud RabbitMQ (CHG-3015)

- 10:20 : CHG-3015 ouvert (journal `docs/qualite/journal/`), annonce à Nadia et Julien ; vérifications : 3 nœuds `running`, aucune alarme, file `notifications` des deux vhosts `quorum` avec 3 membres en ligne, `rabbitmq-queues check_if_node_is_quorum_critical` → aucun risque.
- 10:22:00 : `kubectl -n messagerie delete pod rabbitmq-server-1`.
- 10:22:01 : la file `notifications` de `medinotif-prod` avait son chef sur `rabbitmq-server-1` : élection, nouveau chef en < 2 s ; `medinotif-recette` non touchée (chef ailleurs).
- MédiAgenda : 3 publications sans confirmation (connexion ouverte sur le nœud perdu) → `mediagenda_notifications_total{resultat="echec"}` +3, reconnexion à un autre nœud. MédiNotif : consommateur reconnecté en 2 s.
- 10:23:10 : `rabbitmq-server-1` revenu, son réplica de file rattrape (membres `online` = 3 à 10:23:40).
- 10:30 : CHG-3015 clos.

**Comptes** (fenêtre 10:15-10:35, vhost `medinotif-recette`) : rendez-vous créés **1 204** ; publications confirmées 1 201 + échecs 3 = 1 204 ; notifications traitées par MédiNotif 1 203 dont 2 doublons (`rendez_vous_id` vus deux fois : messages livrés mais non acquittés au moment de la coupure, relivrés) → 1 201 distinctes ; file vide, rebut vide. Les 3 publications en échec ne sont **pas** des notifications perdues par RabbitMQ : elles n'ont jamais été acceptées ; elles sont perdues par **MédiAgenda**, qui ne les republie pas (comportement voulu au M27-E08 : une publication ratée ne fait pas échouer la requête). C'est la limite connue, qui justifie l'*outbox* discutée au M27.

## 4. Garanti contre observé

| Garanti par la conception | Observé ici (une mesure) |
|---|---|
| Aucune transaction validée perdue à la bascule (réplication synchrone, `synchronous` ≥ 1) | aucune ligne manquante (comptage avant/après des rendez-vous créés par k6) |
| Une file quorum de 3 membres survit à la perte d'un nœud ; toute publication confirmée est sur une majorité | 0 message confirmé perdu |
| — | durée des fenêtres d'erreurs, temps de bascule, nombre de doublons : dépendent de la charge, des délais de sonde, du réseau |

## 5. Limites

Une seule mesure de chaque ; recette moins chargée que la prod et une seule instance de Valkey ; la perte d'un nœud RabbitMQ touche aussi la prod (file `medinotif-prod`) : c'est pour cela qu'elle est un changement annoncé, jamais une expérience automatique.

## 6. Actions

| Action | Ticket | Responsable |
|---|---|---|
| Réessayer une fois une transaction en échec de connexion (erreur `OperationalError` avant tout `COMMIT`) | DEV-3015 | équipe MédiAgenda |
| Sonde `/pret` : ne pas sortir tous les pods du Service pendant une bascule de 15 s (délai, seuil d'échec) | DEV-3013 (avec la question du cache) | équipe MédiAgenda |
| *Outbox* des notifications (publications non confirmées republiées), discutée au M27 | DEV-3015-2 | équipe MédiAgenda |
| Maintenance PostgreSQL : toujours `promote`/switchover, jamais suppression de pod | RB-296 | plateforme |
