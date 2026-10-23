# RB-296 — Perte du primaire PostgreSQL ou d'un nœud RabbitMQ sous charge : quoi regarder

| | |
|---|---|
| Ticket d'origine | PLAT-3015 (M29-E15) |
| Quand | alerte de bascule CNPG, nœud RabbitMQ perdu, pic de 5xx de MédiAgenda corrélé à la base ou à la messagerie |
| Principe | **regarder d'abord, agir ensuite** : les deux systèmes se réparent seuls ; une action précipitée (suppression de pod, de PVC, redémarrage de la grappe) aggrave |

## A. Primaire PostgreSQL perdu (`mediagenda-db`)

1. **État** : `kubectl cnpg status mediagenda-db -n <espace>` — phase (`Failing over`, `Cluster in healthy state`), primaire actuel, répliques, réplication synchrone, retard.
2. **Bascule en cours ?** `kubectl -n <espace> get cluster mediagenda-db -o jsonpath='{.status.currentPrimary} {.status.targetPrimary} {.status.currentPrimaryTimestamp}'` ; si `currentPrimary` ≠ `targetPrimary`, attendre (≤ 1 min en général).
3. **Pooler** : `kubectl -n <espace> logs -l cnpg.io/poolerName=mediagenda-db-pooler-rw --since=10m | grep -Ei 'server|closing|login'` ; il doit rouvrir des connexions vers le nouveau primaire sans intervention (il vise le Service `-rw`). Statistiques : `SHOW POOLS;` sur la console d'administration de PgBouncer (base virtuelle `pgbouncer`), si un accès d'administration au pooler a été configuré au M27 ; sinon les métriques du pooler (PodMonitor, `cnpg_pgbouncer_*`).
4. **Application** : 5xx par code et par route, sondes `/pret` (pods prêts). Une fenêtre de 20 à 40 s d'erreurs après une bascule **subie** est le comportement mesuré (rapport PLAT-3015) ; au-delà, chercher : pooler bloqué (`SHOW POOLS` : `cl_waiting` qui monte), Secret ou rôle (journaux du pooler : `password authentication failed`), réseau (Hubble, politiques).
5. **Ne pas** : supprimer un PVC, supprimer l'ancien primaire « pour qu'il revienne », relancer le pooler à la chaîne. L'ancien primaire revient seul en réplique (`pg_rewind`).
6. **Maintenance prévue** : toujours une bascule voulue (`kubectl cnpg promote mediagenda-db <réplique> -n <espace>`), jamais une suppression de pod.

## B. Nœud RabbitMQ perdu (grappe `messagerie/rabbitmq`)

> `messagerie` porte aussi la **prod** : toute action volontaire sur un nœud est un changement annoncé (`CHG-`), un nœud à la fois, après vérification que le quorum n'est pas critique.

1. **Nœuds et alarmes** : API de gestion (compte `wb-checks` ou interface OAuth) `GET /api/nodes` : `running`, `mem_alarm`, `disk_free_alarm` ; `kubectl -n messagerie get pods -l app.kubernetes.io/name=rabbitmq`.
2. **Files** : `GET /api/queues/<vhost>/notifications` (vhost encodé) : `type` = `quorum`, `members`, `online`, `leader`, `messages`. Deux membres sur trois en ligne = la file fonctionne ; un sur trois = **plus de quorum** : la file refuse les publications (ne rien redémarrer d'autre !).
3. **Avant toute action volontaire** : `kubectl -n messagerie exec rabbitmq-server-0 -- rabbitmq-queues check_if_node_is_quorum_critical`.
4. **Clients** : `GET /api/connections` (champ `node`) : les connexions du nœud perdu se reconnectent ailleurs ; MédiAgenda compte les publications non confirmées (`mediagenda_notifications_total{resultat="echec"}`), MédiNotif reconsomme (doublons possibles, livraison « au moins une fois »).
5. **Retour** : le pod revient (StatefulSet) ; son membre de file rattrape (`online` = 3). Si `rabbitmq-server-N` ne revient pas en 5 min : événements du pod, PVC `persistence-rabbitmq-server-N` lié ? alarme disque ? Runbook de la grappe du M27 (`docs/donnees/runbooks/`). **Jamais** de suppression de PVC : on perdrait le membre et ses messages non répliqués… et l'opérateur devrait le reconstruire.
6. **Bilan** : publications acceptées = traitées + en file + au rebut (± doublons expliqués). Un écart non expliqué ouvre un incident.
