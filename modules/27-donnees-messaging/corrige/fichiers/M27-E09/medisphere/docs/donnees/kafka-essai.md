# Essai Kafka (`kafka-essai`)

> `docs/donnees/kafka-essai.md` — M27-E09 (PLAT-2809), M27-E10 (DEV-2810). **ESSAI TEMPORAIRE.**
> Installé le <AAAA-MM-JJ> ; retrait prévu : fin de M27-E10 ; retrait effectif : <AAAA-MM-JJ> (voir en bas).

## Ce qui a été installé

| Élément | Valeur |
|---|---|
| Opérateur | Strimzi **1.3.0** (chart `strimzi-kafka-operator` 1.3.0 recopié par `charts-miroir`, empreinte `sha256:42677cec…1192`), installé dans `kafka-essai`, ne surveille que cet espace ; images `registry.par1.medisphere.internal/quay/strimzi/*` |
| Application | `kafka-essai` (projet `plateforme`) : chart + `valeurs/strimzi/values.yaml` + `plateforme/donnees/kafka-essai/` |
| Grappe | `Kafka` `kafka-essai`, Kafka **4.3.1**, `metadataVersion: 4.3-IV0`, KRaft ; `KafkaNodePool` `double-role` : 3 nœuds `controller`+`broker`, 10 Gio `ceph-rbd` chacun (`kraftMetadata: shared`, `deleteClaim: false`), 1 Gio de mémoire, tas 384 Mio |
| Écouteur | `tls` 9093, interne, TLS (CA de grappe de Strimzi : Secret `kafka-essai-cluster-ca-cert`), SCRAM-SHA-512 ; autorisation `simple` ; Service d'amorce `kafka-essai-kafka-bootstrap.kafka-essai.svc:9093` |
| *Topics* | `rendez-vous.evenements` (3 partitions, facteur 3, `min.insync.replicas` 2, 7 jours) ; `notifications.rebut` (1 partition, facteur 3, 14 jours) |
| Utilisateurs | `mediagenda` (écrire `rendez-vous.evenements`) ; `medinotif` (lire ce *topic* dans le groupe `medinotif`, écrire `notifications.rebut`) ; Secrets du même nom (`password`, `sasl.jaas.config`) |

## Ce que l'opérateur a créé (relevé)

- Pods : `kafka-essai-double-role-0..2` (StrimziPodSet, pas de StatefulSet), `kafka-essai-entity-operator-…` (2 conteneurs : opérateurs de *topics* et d'utilisateurs), `strimzi-cluster-operator-…`.
- PVC `data-0-kafka-essai-double-role-0..2` ; Services `kafka-essai-kafka-bootstrap`, `kafka-essai-kafka-brokers` ; `NetworkPolicy` par écouteur ; `PodDisruptionBudget` (`maxUnavailable` 1).
- Secrets : CA de grappe et CA des clients (certificats et clés), certificats des nœuds, mots de passe des utilisateurs.

## Mesures (à compléter avec TES valeurs)

| Mesure | Valeur |
|---|---|
| Mémoire réservée (requêtes) | ≈ 4,3 Gio (3 × 1 Gio + opérateur 384 Mio + opérateurs d'entité 512 Mio + …) |
| Mémoire réelle (`container_memory_working_set_bytes`) | <MESURE> par nœud au repos, <MESURE> sous charge |
| Disque occupé après le lot d'E10 | <MESURE> |
| Démarrage d'un nœud (pod supprimé → ISR complet) | <MESURE> s |
| Deux nœuds indisponibles, `acks=all`, `min.insync.replicas=2` | le producteur reçoit `NOT_ENOUGH_REPLICAS` (écritures refusées), les lectures des partitions dont le leader survit continuent |

## Retrait

Voir `comparatif-messagerie.md` (décision) et la procédure de M27-E10. Retiré le <AAAA-MM-JJ> : Application, CRD `*.kafka.strimzi.io` et `*.core.strimzi.io`, ClusterRoles du chart, PVC et PV, espace `kafka-essai`, entrée de `charts-miroir`, destination de l'AppProject.
