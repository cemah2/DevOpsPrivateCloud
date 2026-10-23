# Comparatif RabbitMQ / Kafka pour les notifications

> `docs/donnees/comparatif-messagerie.md` — M27-E10 (DEV-2810). Alimente l'ADR-0270 (E17).
> Les valeurs `<MESURE>` sont à remplacer par TES mesures ; les comportements décrits sont ceux attendus
> (et observés lors de la préparation du module sur des courtiers de test).

## Protocole

| Élément | RabbitMQ | Kafka |
|---|---|---|
| Courtier | grappe `messagerie/rabbitmq`, 3 nœuds, 4.3.7, file quorum `notifications` (vhost `medinotif-recette`) | `kafka-essai`, 3 nœuds 4.3.1, *topic* `rendez-vous.evenements` (3 partitions, RF 3, `min.insync.replicas` 2) |
| Producteur | `ressources/E04-messages/publier.py` (confirmations, `mandatory`) | Job `produire-essai` (`kafka-console-producer`, `acks=all`) |
| Consommateur | 2 × MédiNotif (`medinotif-recette`) | 2 × `medinotif-kafka` (`kafka-essai`) |
| Lot | 1 000 valides + 10 invalides (`messages.py` / `publier.py`, même format) | idem |
| Réglages communs | `MEDINOTIF_DELAI_ENVOI_MS=50`, mêmes ressources par worker | idem |

## Mesures

| Mesure | RabbitMQ | Kafka |
|---|---|---|
| Durée de production du lot | <MESURE> | <MESURE> (dont ≈ 5 s de démarrage de la JVM du producteur) |
| Délai fin de production → dernier envoi | <MESURE> | <MESURE> |
| Débit de traitement (`rate(medinotif_messages_total[1m])`) | <MESURE> | <MESURE> |
| Invalides | 10 dans la file `notifications.rebut` (rebut du **courtier**, en-têtes `x-death`) | 10 dans `notifications.rebut` (copie par le **consommateur**, en-têtes `medinotif-*`) |

Avec 50 ms par envoi et deux workers, les deux courtiers sont limités par le **consommateur** (≈ 40 messages/s au plus) : le débit mesuré ne départage pas les courtiers, il départage le nombre de workers. Kafka répartit par **partition** (3 partitions → au plus 3 consommateurs actifs dans le groupe ; un 4e attend) ; RabbitMQ répartit par **message** (préchargement par consommateur).

## Scénarios

| Scénario | RabbitMQ | Kafka |
|---|---|---|
| (a) worker tué au milieu d'un lot | les messages non acquittés du worker reviennent dans la file et sont repris par l'autre : **doublons possibles** (au plus le préchargement), **aucune perte** | rééquilibrage du groupe (après `session.timeout.ms` si le worker est tué net) ; reprise au dernier offset validé : **doublons possibles** (le message en cours), **aucune perte** ; partitions du worker en pause pendant le rééquilibrage (<MESURE> s) |
| (b) un nœud du courtier perdu | file quorum : nouveau leader élu, publications et consommations continuent (confirmations retardées quelques secondes) | partitions dont le leader était sur ce nœud : nouveau leader élu dans l'ISR ; `acks=all` accepté tant que 2 répliques sont à jour ; **deux** nœuds perdus → `NOT_ENOUGH_REPLICAS` |
| (c) consommateur lent (1 s par envoi) | la file grossit (`messages_ready`), visible et alertable ; un worker de plus prend sa part **tout de suite** | le décalage du groupe (*lag*) grossit ; un worker de plus n'aide que s'il reste une partition sans consommateur |
| Message qui échoue toujours (sur le papier) | remis en file à chaque échec ; avec `basic.reject` (correctif de M27-E20), compté par la limite de livraison → rebut au bout de 5 ; avec le `basic.nack` du worker actuel, RabbitMQ 4.3 ne compte pas (« retour ») et le message tourne sans fin — mais dans les deux cas le reste de la file passe | `seek` sur le message : **la partition entière** attend (ordre garanti) jusqu'à une correction ; il faut un *topic* de réessai ou un rebut décidé par le consommateur |

## Coût d'exploitation

| | RabbitMQ (permanent) | Kafka (essai) |
|---|---|---|
| Pods / mémoire réservée | 3 × 1 Gio + opérateurs ≈ 3,6 Gio | 3 × 1 Gio + opérateur + opérateurs d'entité ≈ 4,3 Gio |
| Disque | ≈ ce qui est en file (vide quand tout va bien) | rétention : tout est gardé 7 jours, lu ou non (<MESURE> après le lot) |
| Montée de version | Cluster Operator : redémarrage par roulement, mineure par mineure (E15) | Strimzi : binaires puis `metadataVersion`, opérateur d'abord ; versions Kafka limitées à celles de l'opérateur |
| Topologie, comptes | Messaging Topology Operator (CRD), mots de passe d'OpenBao | `KafkaTopic`, `KafkaUser` (mots de passe générés par Strimzi, à exporter si besoin) |
| Supervision | plugin Prometheus intégré (15692) | exportateur à activer (`kafkaExporter`), métriques JMX à configurer |
| Compétences | déjà dans l'équipe (paliers 1-2) | nouvelles : partitions, groupes, ISR, rétention |

## Ce que chacun fait mieux

- **RabbitMQ** : files de **tâches** — rejet et rebut par message, limite de livraison, file qui se vide, ajout de consommateurs immédiat, routage par échange ; c'est exactement le besoin de MédiNotif.
- **Kafka** : **journal** d'événements — plusieurs lecteurs indépendants du même flux (facturation, statistiques, notifications), relecture du passé, ordre par clé, très hauts débits.

## Recommandation (pour l'ADR-0270)

Garder **RabbitMQ** pour les notifications. Kafka n'apporte rien d'utile **aujourd'hui** (un seul consommateur, pas de relecture) et coûte un composant de plus à exploiter, plus gourmand. Critère de réouverture : un deuxième consommateur **indépendant** des événements de rendez-vous (facturation, statistiques) ou un besoin de relecture. Essai **retiré** (voir `kafka-essai.md`). Backend Kafka du worker : **retiré** par une MR de revert (une dépendance native — `librdkafka` — de moins dans l'image et le SBOM ; il reste dans l'historique Git si l'on rouvre le sujet).
