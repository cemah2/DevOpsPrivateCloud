# NATS et JetStream — fiche découverte

> Fiche courte du module 27 (données et messagerie). NATS **n'est pas installé** dans le lab ; le workbook utilise RabbitMQ 4.3 (décision : ADR-0270, M27-E17). Relevé du 23/10/2026 : serveur NATS **2.15.1** (image officielle `nats:2.15.1`), chart Helm `nats/nats` **2.15.1** (la version du chart suit désormais celle du serveur).

## Ce que c'est

NATS est un système de messagerie écrit en Go, distribué comme un **binaire unique** de quelques dizaines de Mio, projet de la CNCF (niveau *incubating*), sous **licence Apache 2.0**. Il a deux étages :

- **Core NATS** : publication / abonnement sur des **sujets** hiérarchiques (`rdv.confirmation.lyon`, jokers `*` et `>`), requête / réponse, groupes de file (*queue groups* : un seul abonné du groupe reçoit chaque message). Livraison **au plus une fois** : un abonné absent ne reçoit rien, rien n'est stocké.
- **JetStream** (intégré au serveur) : persistance. Un **stream** capture les messages de certains sujets (sur disque ou en mémoire, répliqué sur 1, 3 ou 5 serveurs par Raft) ; des **consumers** (durables, en *pull* ou en *push*) les lisent avec accusé explicite, nouvelle livraison après `ack_wait`, nombre maximal de livraisons (`max_deliver`), délais progressifs (`backoff`), relecture depuis une position (comme un *offset* Kafka). Dédoublonnage à la publication par l'en-tête `Nats-Msg-Id` dans une fenêtre (`duplicate_window`). Sur JetStream sont construits un magasin **clé-valeur** et un magasin **d'objets**.

Autour : comptes et isolation multi-locataires (*accounts*), authentification par NKeys et jetons JWT signés, **leaf nodes** (un petit serveur sur un site distant qui se raccroche au cœur), grappes reliées en **superclusters** (*gateways*). Dans Kubernetes : chart Helm officiel et contrôleur **NACK** (CRD `Stream`, `Consumer`, `KeyValue`… pour déclarer JetStream).

## Cas d'usage typiques

- Messagerie de services **légère** et très rapide (requête / réponse entre microservices, diffusion d'événements).
- **Périphérie** et sites distants : *leaf nodes* qui continuent à fonctionner déconnectés et rattrapent ensuite (magasins, objets connectés, agences).
- File de travail **et** journal rejouable avec le même outil (JetStream), clé-valeur pour de la configuration ou des verrous.

## Comparaison pour le besoin de MédiSphère

| Critère | RabbitMQ 4.3 (retenu) | Kafka 4.3 (essayé, M27-E09/E10) | NATS JetStream 2.15 |
|---|---|---|---|
| Modèle | files, échanges, liaisons ; accusé par message | journal partitionné ; *offset* par groupe | sujets ; streams + consumers ; accusé par message ou relecture |
| File de tâches avec rebut | natif : rejet → échange de rebut, `delivery-limit`, `x-death` | à construire (republication sur un *topic* de rebut) | `max_deliver` puis **avis** (*advisory*) `MAX_DELIVERIES` : le rebut se construit (un consommateur des avis republie ou un stream dédié) |
| Relecture de l'historique | non (sauf *streams* RabbitMQ) | oui, c'est sa raison d'être | oui (consumer depuis une date ou une séquence) |
| Réplication | files quorum (Raft), métadonnées Khepri (Raft) | KRaft + réplication des partitions (ISR) | Raft par stream (R1/R3/R5) et pour les métadonnées |
| Empreinte (3 nœuds, lab) | ≈ 3,5 Gi réservés (3 × 1 Gi + opérateurs) | ≈ 4,5 Gi | quelques centaines de Mio |
| Déclaratif dans Kubernetes | Cluster Operator + Messaging Topology Operator (vhosts, files, politiques, utilisateurs, permissions) | Strimzi (`Kafka`, `KafkaTopic`, `KafkaUser`) | chart + NACK (streams, consumers) ; comptes et utilisateurs par JWT, outillage à part (`nsc`) |
| Compétences dans l'équipe, écosystème | les plus répandues | répandues | plus rares |

## Pourquoi MédiSphère ne le retient pas aujourd'hui

1. **Le besoin est une file de tâches avec rebut**, que RabbitMQ couvre nativement (rejet, limite de livraison, `x-death`, rejeu par *shovel*) ; avec JetStream, le rebut et son exploitation seraient à construire.
2. **Déclaratif incomplet** pour notre façon de travailler : la topologie de RabbitMQ (vhosts, utilisateurs, permissions) est entièrement dans Git par le Topology Operator ; côté NATS, la gestion des comptes et des utilisateurs passe par un outillage séparé.
3. **Une brique de plus à apprendre et à exploiter** sans gain mesurable : nos volumes (≈ 20 messages par seconde au pic du lot de rappels de 18 h en janvier, M27-E16) sont très loin des limites de RabbitMQ.
4. **Gouvernance** : en 2025, l'entreprise qui porte NATS (Synadia) a envisagé de retirer le projet de la CNCF et de changer sa licence ; l'accord trouvé a maintenu NATS à la CNCF sous Apache 2.0. Rien d'inquiétant aujourd'hui, mais un point de vigilance pour une brique centrale.

On rouvrira la question (ADR-0270, conditions de révision) si apparaît un besoin de messagerie **hors du cluster** (sites distants, agences, objets connectés) où les *leaf nodes* font la différence, ou un besoin combiné file de tâches + relecture que ni RabbitMQ seul ni Kafka seul ne couvrent bien.

## Pour essayer (hors lab de référence)

Un conteneur suffit (`nats:2.15.1` avec l'option `-js` pour activer JetStream) et la CLI `nats` : créer un stream sur `rdv.>`, un consumer durable en *pull* avec `max_deliver` et `ack_wait`, publier, consommer, ne pas acquitter, observer les nouvelles livraisons puis l'avis de dépassement (`nats event`). Lis la documentation de **ta** version : les options de la CLI évoluent souvent.

## Liens officiels

- Site et documentation : <https://nats.io> et <https://docs.nats.io>
- JetStream : <https://docs.nats.io/nats-concepts/jetstream>
- Code du serveur : <https://github.com/nats-io/nats-server> (étiquettes `v2.15.x`, fichier `LICENSE`)
- Charts Helm : <https://github.com/nats-io/k8s> ; contrôleur NACK : <https://github.com/nats-io/nack>
- Fiche CNCF : <https://www.cncf.io/projects/nats/>
