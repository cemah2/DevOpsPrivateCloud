# RB-277 — Un consommateur RabbitMQ ne consomme plus

| | |
|---|---|
| Symptôme | Plus de notifications ; la file `notifications` monte ; ou des messages s'accumulent au rebut |
| Alertes | `RabbitmqFileSansConsommateur`, `RabbitmqFileQuiGrossit` (RB-274) ; échecs de publication et rebut (M27-E23) |
| Objets | grappe `messagerie/rabbitmq`, vhosts `medinotif-recette`/`medinotif-prod`, file quorum `notifications`, rebut `notifications.rebut`, Deployment `medinotif` |

Règle : **aucune purge**. Un message qui doit sortir de la file va au rebut (rejet sans remise en file) ; un message au rebut se rejoue, il ne se supprime pas sans décision écrite.

## 1. Trois chiffres

```
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_queues -p <VHOST> name type consumers messages_ready messages_unacknowledged
```
et, dans l'interface (ou `GET /api/queues/<VHOST>/notifications`), `message_stats.redeliver_details.rate`.

| Constat | Piste |
|---|---|
| `consumers = 0`, MédiNotif se reconnecte en boucle | §2 accès ou configuration |
| `consumers = 0`, aucun pod MédiNotif | réplicas à zéro (Git de `medinotif/deploiement`, plus tard KEDA) |
| `consumers ≥ 1`, 1 message non acquitté, redélivrances, pods qui redémarrent | §3 message empoisonné |
| `consumers ≥ 1`, débit faible, file qui monte | consommateurs trop lents : réplicas (RB-274) |

## 2. Accès et configuration

- Journaux : `kubectl -n <ESPACE> logs deploy/medinotif --since=10m` (`ACCESS_REFUSED`, `NOT_FOUND - no queue`, `PRECONDITION_FAILED`, `ACCESS_REFUSED - Login was refused`).
- Droits en vigueur : `rabbitmqctl list_user_permissions <UTILISATEUR>` ; comparer à la `Permission` déclarée dans `plateforme/donnees/topologie/<vhost>/` et à son historique Git. Un changement de permission ne vaut que pour les **nouveaux** canaux : après correction, les clients se reconnectent d'eux-mêmes (ou fermer leurs connexions : `DELETE /api/connections/username/<UTILISATEUR>`).
- Nom de file, vhost, URL : variables effectives du Deployment (`MEDINOTIF_FILE`, `MEDINOTIF_AMQP_URL` par l'ExternalSecret) contre la topologie déclarée. Avec `MEDINOTIF_DECLARER_FILE=0`, une file mal nommée n'est **pas** créée : `NOT_FOUND`.
- Corriger dans Git (topologie ou overlay), laisser Argo CD et le Topology Operator appliquer.

## 3. Message empoisonné

1. Le message en tête : `rabbitmq-queues peek --vhost <VHOST> notifications 1` (sans le consommer). Les journaux du conteneur qui a planté : `kubectl -n <ESPACE> logs deploy/medinotif --previous`.
2. Pourquoi il revient : la limite de livraison. `GET /api/queues/<VHOST>/notifications` → `effective_policy_definition["delivery-limit"]` (et `arguments["x-delivery-limit"]`). Défaut 20 en RabbitMQ 4.x ; `-1` = **sans limite**. En 4.3, la limite compte les rejets (`basic.reject`) et les fermetures de canal avec des messages non acquittés (un plantage), **pas** les `basic.nack` avec remise en file.
3. Remettre la limite (Policy dans Git). Le message part au rebut après la limite ; s'il bloque encore, MédiNotif étant arrêté (`CrashLoopBackOff`, en attente), le rejeter **sans remise en file** depuis l'interface (« Get messages », mode « Reject requeue false ») après avoir vérifié par `peek` que c'est bien lui en tête : il est dead-letteré vers le rebut, pas supprimé.
4. Corriger MédiNotif : toute exception inattendue sur un message doit donner un rejet, jamais un arrêt du processus (correctif `message-empoisonne.patch`, M27-E20).

## 4. Rejouer le rebut sans doublon

1. **Regarder avant de rejouer** : `rabbitmq-queues peek --vhost <VHOST> notifications.rebut 1`, puis l'en-tête `x-death` de quelques messages : `reason` (`rejected` = MédiNotif l'a jugé invalide : **ne pas** le rejouer tel quel ; `maxlen`, `expired`, `delivery_limit` = victime d'un incident : à rejouer), `queue` d'origine, `count`, `time`.
2. **Doublons** : un message `maxlen` ou `expired` n'a jamais été traité ; un message `delivery_limit` peut l'avoir été partiellement (envoi fait, acquittement perdu) : vérifier dans les journaux de MédiNotif (`rendez_vous_id`, `modele`) avant de le rejouer, tant que MédiNotif n'est pas idempotent (ADR-0270).
3. **Rejouer** : un `Shovel` du Topology Operator (CR dans `plateforme/donnees/topologie/<vhost>/`, modèle `shovel-rejeu.yaml` de M27-E23) de `notifications.rebut` vers `notifications`, `srcDeleteAfter: queue-length` (il s'arrête une fois la file source vidée de ce qu'elle contenait au départ), puis retirer le CR. Plugin `rabbitmq_shovel` requis (`additionalPlugins` du `RabbitmqCluster`). Les messages invalides repartiront au rebut : les trier d'abord si le rebut en contient beaucoup.
4. Vérifier : rebut vidé de l'incident, `medinotif_messages_total{resultat="envoye"}` qui augmente d'autant, aucune alerte.
