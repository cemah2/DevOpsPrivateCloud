# Montée de RabbitMQ 4.3 → 4.4 : répétition et décision (M27-E15, CHG-2815)

| | |
|---|---|
| Date | <AAAA-MM-JJ> |
| Grappe de production | `messagerie/rabbitmq`, 3 nœuds, RabbitMQ 4.3.7, Cluster Operator 2.23.1 |
| Répétition | `wb-essais/rabbitmq-essai` (`plateforme/donnees/rabbitmq-essai/`), 3 nœuds, 4.3.7 → 4.4.0 |
| Décision | **rester en 4.3.7** jusqu'à la 4.4.1, au plus tard le 15/12/2026 (fin du support communautaire de la 4.3 : 01/2027) |

> Exemple du lab de référence : écris **tes** constats et **ta** décision. Les deux issues sont acceptables si elles sont justifiées.

## Répétition

1. Grappe jetable en 4.3.7 ; vhost `essai` réimporté depuis l'export de `medinotif-recette` (`POST /api/definitions/essai`) : échange `notifications`, files `notifications` (quorum) et `notifications.rebut`, politiques — import sans erreur.
2. 1 000 messages persistants dans une file quorum et 1 000 dans une file classique (`messages-essai.sh preparer`).
3. `rabbitmqctl list_feature_flags name state` : tous `enabled` sur les trois nœuds ; `rabbitmq-queues check_if_node_is_quorum_critical` : aucun nœud critique.
4. Changement d'`image` en `4.4.0-management` : l'opérateur redémarre `server-2`, puis `server-1`, puis `server-0` ; chaque nœud repart en 40 à 60 s ; pendant le redémarrage du nœud qui porte le leader de `essai-quorum`, un nouveau leader est élu (terme +1 dans `quorum_status`), la file reste disponible (perf-test en fond : pas d'échec de publication, latence p99 à 1,4 s pendant l'élection).
5. Après : 1 000 + 1 000 messages retrouvés (`messages-essai.sh compter`) ; `autoEnableAllFeatureFlags` a activé les nouveaux *feature flags* de la 4.4 ; l'opérateur 2.23.1 ne signale aucune erreur (compatibilité non annoncée, constatée sur cet essai seulement).
6. **Retour en 4.3.7** (image remise) : le nœud redémarré ne démarre plus (les *feature flags* de la 4.4 activés sont inconnus de la 4.3, et le stockage v2 des files classiques n'est pas relu) ; seule issue : supprimer la grappe et ses volumes. **Aller simple confirmé.**

## Décision et raisons

- La répétition est **réussie** : la montée est techniquement possible sans perte.
- Mais la 4.4.0 a trois jours, et la compatibilité du Cluster Operator 2.23 avec la 4.4 n'est pas annoncée par ses notes de version ; une montée irréversible sur une `.0` n'apporte rien à MédiNotif aujourd'hui (aucune fonction de la 4.4 attendue).
- Donc : **rester en 4.3.7**, refaire la répétition sur la 4.4.1 (ou sur une version de l'opérateur qui annonce la 4.4), et monter au plus tard le 15/12/2026 pour ne pas dépasser la fin du support de la 4.3.

## Si on applique (procédure retenue)

MR sur `plateforme/donnees/rabbitmq/rabbitmqcluster.yaml` (image `4.4.x-management`, `autoEnableAllFeatureFlags: true`), en fenêtre annoncée (CHG-28xx), après : export manuel des définitions, *feature flags* tous actifs, aucune file quorum critique, aucune alarme, MédiNotif de production à jour de sa file. Pendant : suivi de `quorum_status` des files `notifications` des deux vhosts et du tableau `m27-donnees`. Après : version de chaque nœud (`rabbitmq-diagnostics server_version`), files et messages, consommateurs, alertes vertes. Pas de retour arrière possible : le plan de secours est la restauration des définitions sur une grappe neuve (RB-275), les messages en vol étant alors perdus.
