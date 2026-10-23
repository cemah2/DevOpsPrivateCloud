# RB-271 — RabbitMQ (`messagerie/rabbitmq`) : redémarrage d'un nœud par roulement

> M27-E12 (PLAT-2812), facultatif. Propriétaire : plateforme.

## Avant

```
admin@adm01:~$ kubectl -n messagerie get rabbitmqcluster rabbitmq -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics check_running
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics check_local_alarms
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-queues check_if_node_is_quorum_critical
```
`check_if_node_is_quorum_critical` doit réussir **pour le nœud à arrêter** (exécuté dans son pod) : sinon, une file quorum perdrait sa majorité.

## Un nœud

```
admin@adm01:~$ kubectl -n messagerie delete pod rabbitmq-server-<n>      # un seul ; le StatefulSet le recrée (même PVC)
admin@adm01:~$ kubectl -n messagerie wait --for=condition=Ready pod/rabbitmq-server-<n> --timeout=10m
```
Puis, avant le suivant : `rabbitmq-diagnostics check_running` sur le nœud revenu, toutes les files quorum avec 3 membres en ligne (`rabbitmq-queues quorum_status notifications --vhost medinotif-<env>`), consommateurs de `notifications` revenus (MédiNotif se reconnecte seul).

Pour TOUS les nœuds (changement de configuration) : laisser l'opérateur faire, par une MR sur le `RabbitmqCluster` — il met à jour le StatefulSet, et son crochet d'arrêt (`preStop`) attend qu'un nœud ne soit plus critique pour les files quorum avant de le laisser s'arrêter.

## Interdits

`rabbitmqctl forget_cluster_node`, `rabbitmqctl reset`, `force_boot`, suppression d'un PVC, purge d'une file : réservés au niveau 2 avec un ticket (perte de données).
