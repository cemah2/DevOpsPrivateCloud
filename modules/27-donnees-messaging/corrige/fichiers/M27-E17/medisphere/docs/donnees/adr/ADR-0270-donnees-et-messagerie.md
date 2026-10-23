# ADR-0270 — Données et messagerie de MédiSphère

- **Statut** : accepté (comité d'architecture du <AAAA-MM-JJ>)
- **Décideurs** : Claire Morel, Karim Benali, Sophie Laurent ; consultés : Julien Petit, Nadia Roussel
- **Contexte lié** : ADR-0140 (Kubernetes), ADR-0200 (GitOps), ADR-0251 (secrets), PLAN §4.13 ; essais M27-E09/E10 (Kafka), M27-E13 (Patroni), M27-E16 (mesures)

## Contexte

MédiAgenda prend des rendez-vous (PostgreSQL, Valkey en cache) et doit faire envoyer des confirmations et des rappels par MédiNotif, de façon **asynchrone** (une passerelle SMS lente ne doit pas ralentir la prise de rendez-vous) et **fiable** (« un rappel perdu, c'est un patient qui ne vient pas »). Contraintes : données de santé (HDS), souveraineté (tout dans nos salles), une petite équipe plateforme, des briques libres et pérennes. Volumes (M27-E16) : 3 000 rendez-vous par jour, ×4 en janvier ; au plus 20 notifications par seconde (lot des rappels de la veille) ; quelques dizaines de transactions par seconde en pointe.

## Décision 1 — Messagerie : RabbitMQ (files quorum)

**RabbitMQ 4.3** par le Cluster Operator et le Messaging Topology Operator, grappe de trois nœuds `messagerie/rabbitmq`, files **quorum** uniquement, un vhost par environnement, échange de rebut et limite de livraison, topologie et identités déclarées dans Git (`plateforme/donnees`), secrets dans OpenBao. Le besoin est une **file de tâches** : un message, un consommateur qui le traite, l'acquitte ou le rejette ; un rebut pour ce qui échoue ; aucun besoin de relire l'historique.

| Option | Pour | Contre | Verdict |
|---|---|---|---|
| **RabbitMQ** | modèle file de tâches natif (accusés par message, rejet, rebut, limite de livraison) ; files quorum (Raft) ; métadonnées Khepri ; ~400 publications confirmées/s par connexion et ~7 000 msg/s en lot (M27-E16), marge ×20 | une grappe Erlang de plus à exploiter ; montées mineures irréversibles (4.4) | **retenu** |
| Kafka (Strimzi 1.3, KRaft, essayé en M27-E09/E10) | journal rejouable, plusieurs consommateurs indépendants, débit énorme | pas d'accusé ni de rebut par message (un *offset* par partition : un message empoisonné bloque la partition ou doit être republié à la main sur un *topic* de rebut) ; ≈ 4,5 Gi de mémoire pour trois nœuds (contre ≈ 1,5 Gi) ; une compétence de plus ; aucun deuxième consommateur aujourd'hui | **écarté pour l'instant** |
| NATS JetStream 2.15 (fiche `annexes/decouverte/nats.md`) | léger, un seul binaire, accusés et redélivrance, flux persistants | pas d'opérateur de topologie équivalent (CRD NACK moins abouties), communauté et compétences internes plus minces, pas de gain sur notre besoin | **non retenu** |
| Table PostgreSQL utilisée comme file (`SELECT … FOR UPDATE SKIP LOCKED`) | aucune brique de plus, transactionnel avec le rendez-vous | charge et verrous sur la base critique, consommateurs à écrire, supervision à inventer | écarté (mais voir Décision 4) |

## Décision 2 — PostgreSQL : CloudNativePG

Les bases des applications du cluster restent sur **CloudNativePG 1.30** (réplication synchrone `ANY 1`, `dataDurability: required`, *pooler* PgBouncer, archivage par le plugin Barman Cloud, réplica de secours depuis le stockage objet).

| Option | Mesures (M27-E13, lab de référence) | Verdict |
|---|---|---|
| **CloudNativePG** | bascule planifiée 4,1 s, sur panne 12 s, 0 validation perdue | **retenu** |
| Patroni 4.1 sur VMs (etcd) | bascule planifiée 6,8 s, sur panne 31 s (`ttl` 30), 0 validation perdue ; point d'accès, sauvegarde, TLS et supervision **à construire** ; trois VMs de plus à exploiter | réservé à une base hors Kubernetes (comparatif `comparatif-patroni-cnpg.md`) |

## Décision 3 — Migrations de schéma : Flyway Community

**Flyway 13 Community** (image construite par la CI de `mediagenda/api`, Job hook Argo CD, compte de migration dynamique), migrations **expand/contract**.

| Option | Licence (fichier `LICENSE` du dépôt, version utilisée) | Pour | Contre | Verdict |
|---|---|---|---|---|
| **Flyway 13 Community** | **Apache License 2.0** (dépôt `flyway/flyway`) | SQL pur, simple, `baseline` d'une base existante, `validate` en CI | `undo` réservé aux éditions payantes (on ne s'en sert pas : on corrige en avant) | **retenu** |
| Liquibase 5.0 | **FSL-1.1-ALv2** (*Functional Source License*, convertie en Apache 2.0 après deux ans) depuis 5.0 : n'est plus une licence libre au sens de l'OSI | changelogs multi-formats, *rollback* | licence non libre ; pilotes JDBC et extensions non fournis (`liquibase lpm add`) | écarté |
| Atlas 1.3 | **Apache 2.0 pour l'édition Community seulement** (`arigaio/atlas:latest-community`) ; binaire standard sous licence propriétaire | schéma déclaratif, *diff* | `migrate lint`, `schema plan` et l'opérateur Kubernetes exigent un compte Pro | écarté |

## Décision 4 — Cohérence entre la base et les messages

Aujourd'hui, MédiAgenda valide la transaction du rendez-vous **puis** publie la demande de notification (avec confirmation de publication) ; une publication ratée est journalisée et comptée (`mediagenda_notifications_total{resultat}`), **pas rejouée** : un pod tué entre les deux, ou un courtier indisponible, perd la notification. Nous l'acceptons pour l'instant, avec une alerte sur les échecs de publication (M27-E23).

Évolution décidée : le motif ***outbox*** transactionnel. MédiAgenda écrit la demande de notification dans une table `notifications_a_envoyer` **dans la même transaction** que le rendez-vous ; un relais (processus de MédiAgenda ou petit service) lit cette table (`FOR UPDATE SKIP LOCKED`), publie avec confirmation, marque la ligne comme envoyée. Garantie : au moins une fois, donc **MédiNotif doit être idempotent** (clé : identifiant de la demande, conservé 7 jours). La capture des changements (Debezium sur le WAL) est écartée : une brique Kafka Connect de plus pour un besoin qu'une table et un relais couvrent.

## Conséquences

- Plateforme : une grappe RabbitMQ à exploiter (supervision et alertes M27-E14, export nocturne des définitions et montée de version répétée M27-E15, runbooks RB-274 à RB-279) ; CloudNativePG reste le seul chemin pour PostgreSQL dans le cluster.
- Sécurité : identités par application et par environnement (publication seule pour MédiAgenda, consommation seule pour MédiNotif), TLS (AMQPS 5671) dans le cluster, compte par défaut de RabbitMQ en bris de glace ; un compte `administrator` existe pour l'export des définitions (écart justifié, sans permission sur les vhosts). Aucune image ni aucun chart Bitnami.
- Équipes : MédiNotif garde un traitement idempotent et transforme toute exception inattendue en rejet (pas en arrêt) ; MédiAgenda prépare l'*outbox*.

## Critères de révision

- **Kafka** revient sur la table le jour où un **deuxième consommateur** doit relire les événements de rendez-vous de façon indépendante (statistiques, facturation, synchronisation d'agendas externes), ou si le volume dépasse quelques milliers de messages par seconde soutenus.
- **NATS** est réévalué si un besoin de messagerie légère hors du cluster apparaît (sites distants, objets connectés).
- **Outbox** : obligatoire avant d'ouvrir les rappels à des centres hors recette élargie, ou dès un deuxième incident de notifications perdues.
- **Liquibase / Atlas** : seulement si leur licence redevient libre et qu'un besoin (multi-bases, *diff* déclaratif) apparaît.
- **RabbitMQ** : fin du support communautaire de la 4.3 (01/2027) — montée en 4.4 décidée dans `montee-rabbitmq-4.4.md`.
