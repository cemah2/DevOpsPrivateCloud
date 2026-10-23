# Module 27 — Introduction : données et messagerie

## « Un SMS de rappel perdu, c'est un patient qui ne vient pas »

Lundi, 9 h 10. Le comité d'architecture vient de finir, et Claire Morel n'a pas l'air ravie. Julien Petit y a présenté les chiffres du support : 6 % de rendez-vous non honorés le mois dernier, et une même remarque dans la moitié des appels — « on ne m'a rien envoyé ». MédiNotif, le worker de notifications construit au module 12, tourne toujours… sur `ctr01`, une VM de formation qui n'existe plus. Nadia Roussel a enchaîné sur la base : « Quand le primaire de `mediagenda-db` est tombé en recette jeudi, personne ne savait s'il fallait attendre ou agir. » Et Karim a conclu, agacé, sur la troisième discussion du trimestre à propos de Kafka. Claire écrit à l'équipe.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Julien Petit, Nadia Roussel, Sophie Laurent
> **Objet** : Données et messagerie — on sort du provisoire
>
> Bonjour,
>
> Nos données tiennent, mais par habitude plus que par conception. Ce que je veux à la fin du module :
> 1. **PostgreSQL exploité, pas seulement installé** : rôles et bases déclarés dans Git, une réserve de connexions devant `mediagenda-db`, des bascules que l'astreinte sait faire et un runbook pour les faire ;
> 2. des **migrations de schéma** qui ne cassent jamais la version de l'API qui tourne encore : on abandonne le script maison pour **Flyway** ;
> 3. un **Valkey** à jour, protégé (ACL, TLS) et borné en mémoire : c'est un cache, sa perte doit dégrader, pas casser ;
> 4. une **messagerie** fiable : RabbitMQ, déployé par ses opérateurs, sa topologie dans Git, MédiNotif enfin en recette puis en production, et MédiAgenda qui publie les demandes de notification ;
> 5. **Kafka essayé, mesuré, puis retiré**, avec une décision écrite : je ne veux plus de débat sans données.
>
> Contraintes : tout par le code et par Argo CD ; aucun secret dans Git (OpenBao + External Secrets, M25) ; Pod Security `restricted` et images signées en recette et en production (M26) ; **aucune image ni chart Bitnami**. Karim te fait passer le test habituel avant de commencer.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 27, MédiSphère a ses données et sa messagerie **v1** (étiquette `donnees-v1` du dépôt `plateforme/medisphere`), que le module 28 utilise pour la mise à l'échelle (KEDA sur la file `notifications`) et le module 29 pour les essais de charge et de chaos.

| Exercice | Ce que tu construis | Où |
|---|---|---|
| E01 | Ton positionnement (questionnaire) | — |
| E02 | Rôles et base déclaratifs, `pg_stat_statements`, Pooler **`mediagenda-db-pooler-rw`** (PgBouncer, mode transaction) devant `mediagenda-db` ; bascule, nœud drainé, image mise à jour ; ClusterRole **`wb-checks-services`** | `mediagenda-recette`, `mediagenda-prod`, `plateforme/k8s` |
| E03 | Cluster Operator 2.23 et Messaging Topology Operator 1.20 ; grappe **`rabbitmq`** de trois nœuds, TLS, interface de gestion par SSO | `rabbitmq-system`, `messagerie`, `plateforme/donnees` |
| E04 | Topologie déclarative du vhost **`medinotif-recette`** ; **MédiNotif en recette** (dépôt `medinotif/deploiement`, ApplicationSet `medinotif`) | `messagerie`, `medinotif-recette` |
| E05 | **Flyway 13** reprend les migrations de MédiAgenda (`baseline` à la version 2), Job **`mediagenda-migrations`** | `mediagenda/api`, `mediagenda/deploiement` |
| E06 | Une évolution du schéma en deux temps (*expand* puis *contract*), testée contre la version N−1 | `mediagenda/api` |
| E07 | **Valkey 9.1** : montée de version, ACL, TLS, éviction, exportateur | `mediagenda/deploiement` |
| E08 | MédiAgenda publie les notifications ; **MédiNotif en production** | `mediagenda/api`, `medinotif-prod` |
| E09 | **Strimzi 1.3**, Kafka 4.3.1 KRaft `kafka-essai` (temporaire) | `kafka-essai` |
| E10 | MédiNotif sur Kafka, **comparaison mesurée**, puis **retrait** complet de Kafka | `medinotif/worker`, `docs/donnees/` |
| E11 | Revue des manifestes de Lucas | — |
| E12 | Runbook RB-270 : maintenance et bascule de PostgreSQL (et RB-271 : RabbitMQ) | `docs/donnees/runbooks/` |
| E13-E18 | Patroni en comparaison, supervision, réplica de secours et RabbitMQ 4.4, performance, ADR-0270, questions de production | palier 3 |
| E19-E24 | Cinq pannes et une plongée sous le capot (réplication synchrone, WAL, Raft) | palier 4 |
| E25 | Mini-projet : `donnees-v1` | palier 5 |

Le **palier 1** (ce fichier et `01-decouverte.md`) approfondit CloudNativePG, installe RabbitMQ et sa topologie, déploie MédiNotif en recette et passe les migrations à Flyway. Le **palier 2** (`02-operationnel.md`) traite les tickets du quotidien : une évolution de schéma sans interruption, Valkey 9, la mise en production des notifications, l'essai de Kafka, une revue et le runbook d'astreinte. Le **palier 3** (`03-production.md`) compare avec Patroni, supervise, prépare la reprise et la montée de version, mesure et écrit l'ADR-0270. Le **palier 4** (`04-expert.md`) casse et répare. Le **mini-projet** (`05-mini-projet.md`) livre `donnees-v1`.

## Architecture du module (fin du palier 2)

```
                         adm01 (MGMT) : kubectl, kubectl cnpg, bao, lab/bin/check 27 …
                                │ HTTPS 443 (SSO Keycloak ; API en authentification basique pour wb-checks)
  ═════════════════════════════ k8s-par1 ══════════▼═══════════════════════════════════════════════════
  │  passerelles/gw-par1 (10.10.41.10) ── HTTPRoute rabbitmq.apps.par1.medisphere.internal ──┐       │
  │                                                                                          ▼ 15672 │
  │  espace rabbitmq-system                     espace messagerie                                    │
  │  ┌─────────────────────────────┐            ┌──────────────────────────────────────────────┐     │
  │  │ Cluster Operator 2.23       │──gère────► │ RabbitmqCluster « rabbitmq » 4.3 (3 nœuds)   │     │
  │  │ Messaging Topology Op. 1.20 │──API 15671►│  Khepri (Raft) · files quorum · TLS 5671     │     │
  │  └─────────────────────────────┘            │  vhosts medinotif-recette, medinotif-prod    │     │
  │                                             │  échange notifications ─► file notifications │     │
  │                                             │  rebut : notifications.rebut                 │     │
  │                                             └───────▲─────────────────────────▲────────────┘     │
  │   AMQPS 5671 (publication, confirmations)           │                         │ AMQPS 5671       │
  │  ┌──────────────────────────────────────┐           │      ┌──────────────────┴───────────┐      │
  │  │ mediagenda-recette / -prod           │───────────┘      │ medinotif-recette / -prod    │      │
  │  │  Rollout mediagenda (API)            │                  │  Deployment medinotif        │      │
  │  │    │ 5432            │ rediss 6379   │                  │  (envoi simulé, métr. 9100)  │      │
  │  │    ▼                 ▼               │                  └──────────────────────────────┘      │
  │  │  Pooler mediagenda-db-pooler-rw   StatefulSet valkey (9.1, ACL, TLS, exportateur 9121)       │
  │  │  (PgBouncer, transaction)         │                                                          │
  │  │    │ 5432                         Job mediagenda-migrations (Flyway, hook Sync −1) ─┐         │
  │  │    ▼                                                                              │ 5432    │
  │  │  Cluster mediagenda-db (CNPG 1.30, PostgreSQL 18, 3 instances) ◄──────────────────┘         │
  │  │    └─ WAL et sauvegardes → plugin Barman Cloud → s3-01 (cnpg-k8s-par1)                      │
  │  └──────────────────────────────────────┘                                                      │
  │  espace kafka-essai (E09 → fin d'E10 seulement) : Strimzi 1.3, Kafka 4.3.1 KRaft, 3 nœuds        │
  ════════════════════════════════════════════════════════════════════════════════════════════════
  OpenBao (vault01-03) : kv/<application>/<env>/{amqp,valkey}, identifiants dynamiques PostgreSQL (M25)
```

---

## Le chemin imposé

1. **Opérateurs et services de plateforme par Argo CD** : charts recopiés et signés dans Harbor par `plateforme/charts-miroir` ; quand le projet ne publie **pas** de chart (opérateurs RabbitMQ), ses manifestes de publication sont **recopiés et épinglés** (empreinte vérifiée) dans `plateforme/donnees/vendor/`, puis appliqués par une Application. Le cluster ne tire jamais rien d'Internet : images par le cache Harbor (`registry.par1.medisphere.internal/{dockerhub,ghcr,quay}/…`).
2. **Nouveau projet `plateforme/donnees`** (clone `~/src/donnees`) : `vendor/rabbitmq/`, `rabbitmq/`, `topologie/`, `kafka-essai/`, `patroni-essai/` (palier 3), `outils/`. Applications Argo CD dans `plateforme/gitops/plateforme/` ; valeurs des charts dans `plateforme/gitops/valeurs/<composant>/`.
3. **Espaces** (`messagerie`, `rabbitmq-system`, `medinotif-recette`, `medinotif-prod`, `kafka-essai`) : dans `plateforme/k8s/espaces/`, avec leurs étiquettes Pod Security, quotas et `LimitRange`, appliqués par `task appliquer` comme depuis le M14.
4. **Applications** : rien n'est appliqué à la main sur les espaces applicatifs (M20). MédiAgenda par `mediagenda/deploiement` ; MédiNotif par le nouveau dépôt **`medinotif/deploiement`** (même modèle).
5. **Secrets** : OpenBao (`kv/<application>/<env>/<secret>`), lus par External Secrets (SecretStore `openbao` de l'espace, ou ClusterSecretStore `openbao` pour les espaces de plateforme) ; les identifiants PostgreSQL restent **dynamiques** (M25).
6. **Réseau** : CiliumNetworkPolicy par espace (refus par défaut), flux reportés dans `docs/socle/matrice-flux.md` ; aucun flux ne quitte le cluster dans ce palier (AMQPS 5671 est **interne**).
7. **Documentation** : `plateforme/medisphere`, dossier `docs/donnees/` (`adr/`, `runbooks/`).

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**CloudNativePG au-delà du M16.** Au M16, tu as installé l'opérateur et créé `mediagenda-db` (trois instances, réplication synchrone `any 1`, archivage par le plugin Barman Cloud). L'opérateur ne gère pas seulement des pods : il **réconcilie** l'état de PostgreSQL lui-même. Les rôles listés dans `spec.managed.roles` sont créés, modifiés, révoqués à chaque réconciliation (un rôle absent de la liste n'est pas touché ; une appartenance absente de `inRoles` est retirée) ; la CRD `Database` fait de même pour une base (propriétaire, extensions, schémas). Les bascules sont **pilotées** : un *switchover* (planifié, sans perte) par `kubectl cnpg promote`, un *failover* (subi) quand le primaire disparaît ; un changement de `imageName` déclenche une mise à jour progressive (réplicas d'abord, puis bascule et ancien primaire en dernier). Champ immuable à connaître : `spec.cluster` d'un `Pooler`, d'une `Database` ou d'une `ScheduledBackup` — pour viser une autre base, on recrée l'objet.

**La réserve de connexions (*pooler*).** Chaque connexion PostgreSQL est un **processus** du serveur (plusieurs Mio de mémoire, un coût d'ouverture de quelques millisecondes). Trois pods de l'API avec dix connexions chacun pendant un *canary*, plus le Job de migration, plus les identifiants dynamiques qui tournent : on approche vite de `max_connections`. **PgBouncer** garde quelques connexions serveur ouvertes et y fait passer beaucoup de clients. En mode **session**, un client garde sa connexion serveur jusqu'à sa déconnexion (gain faible) ; en mode **transaction**, il ne la garde que le temps d'une transaction (gain fort), mais tout ce qui vit **entre** les transactions casse : `SET` de session, verrous consultatifs de session (`pg_advisory_lock`), `LISTEN`, tables temporaires, et — avant PgBouncer 1.21 — les instructions préparées. D'où une règle : l'API passe par le pooler en mode transaction, les **migrations** (verrous de session, DDL longs) vont **directement** au primaire.

**Migrations rétrocompatibles (*expand/contract*).** Pendant un déploiement progressif (canary, M20), deux versions de l'API tournent ensemble sur **le même** schéma ; et le Job de migration passe **avant** la nouvelle version (vague −1). Une migration doit donc toujours être compatible avec la version **précédente** de l'application. On découpe tout changement cassant en deux : **expand** (ajouter : colonne facultative ou avec défaut, nouvelle table, contrainte `NOT VALID`) livré d'abord, puis la nouvelle version de l'application, puis **contract** (retirer, durcir) quand plus aucune ancienne version ne tourne nulle part. Les verrous comptent autant que le SQL : un `ALTER TABLE` qui attend son verrou bloque toutes les requêtes derrière lui — `lock_timeout` le fait échouer vite.

**Flyway.** Un outil de migrations versionnées : des fichiers `V<version>__<description>.sql` appliqués dans l'ordre, une table d'historique (`flyway_schema_history`) avec la **somme de contrôle** de chaque fichier, un verrou pour qu'une seule exécution migre à la fois. `baseline` reprend une base existante en déclarant « tout ce qui est en dessous de la version N est déjà appliqué ». `validate` refuse un fichier déjà appliqué puis modifié. L'édition libre (*OSS*, Apache 2.0) suffit ici ; les annulations (`undo`) sont réservées aux éditions payantes — on ne revient pas en arrière, on corrige **en avant**.

**Valkey comme cache.** Valkey (la suite libre de Redis) garde des données en mémoire. Pour MédiAgenda, c'est un **cache** de créneaux : sa perte coûte des lectures en base, pas des données. Il faut donc surtout le **borner** (`maxmemory`), choisir quoi évincer quand il est plein (`allkeys-lru` : la clé la moins récemment lue), le **protéger** (ACL : un utilisateur par usage, `default` désactivé ; TLS) et le **superviser**. La réplication et Sentinel apportent la disponibilité… à un client qui sait parler à Sentinel, ce que MédiAgenda ne sait pas faire.

**RabbitMQ et AMQP 0-9-1.** Un éditeur publie un message sur un **échange** (*exchange*), qui le **route** vers des **files** (*queues*) selon des **liaisons** (*bindings*) et une clé de routage ; un consommateur lit une file et **acquitte** (`ack`) chaque message après l'avoir traité, ou le **rejette** (`nack`), avec ou sans remise en file. Côté éditeur, les **confirmations de publication** (*publisher confirms*) disent si le courtier a pris le message en charge ; l'option `mandatory` fait revenir un message qu'aucune file n'a reçu. Un **vhost** cloisonne les objets (un par environnement ici) ; les **permissions** (configurer, écrire, lire, par expressions régulières) cloisonnent les utilisateurs.

**Files quorum et Khepri.** Une file **quorum** est répliquée sur plusieurs nœuds par **Raft** : une écriture n'est confirmée que quand une **majorité** des répliques l'a écrite sur disque ; si le nœud leader tombe, une autre réplique est élue sans perte. Elle remplace les anciennes files miroir classiques, **supprimées en RabbitMQ 4.0**. Elle compte les livraisons de chaque message : passé la **limite de livraison**, le message part au **rebut** (*dead letter exchange*) au lieu de boucler indéfiniment. Les **métadonnées** de la grappe (vhosts, utilisateurs, définitions des files) sont elles-mêmes dans **Khepri**, un magasin Raft, par défaut depuis RabbitMQ 4.2 (Mnesia avant) : trois nœuds tolèrent la perte d'un nœud, pas de deux.

**Au moins une fois, et l'idempotence.** Un message acquitté **après** son traitement n'est jamais perdu si le consommateur meurt… mais il peut être traité **deux fois** (traité, puis consommateur tué avant l'acquittement). Côté éditeur, une publication dont la confirmation se perd est republiée. La livraison « exactement une fois » de bout en bout n'existe pas sans effort applicatif : le consommateur doit être **idempotent** (reconnaître un message déjà traité, par un identifiant).

**Kafka.** Un **journal** d'événements partitionné et répliqué : les messages sont ajoutés à la fin d'une **partition**, gardés pendant une durée de rétention qu'ils aient été lus ou non, et chaque **groupe de consommateurs** retient sa position (**offset**) dans chaque partition. Plusieurs groupes relisent le même journal indépendamment ; l'ordre n'est garanti que **dans** une partition. La durabilité dépend du facteur de réplication, de `min.insync.replicas` et de `acks=all` côté producteur ; l'ensemble des répliques à jour s'appelle l'**ISR**. Depuis Kafka 4.0, **KRaft** (Raft interne) remplace ZooKeeper ; avec **Strimzi**, les nœuds se déclarent par **pools** (`KafkaNodePool`) aux rôles `controller` et/ou `broker`.

**File de tâches ou journal d'événements ?** RabbitMQ distribue des **tâches** : chaque message va à **un** consommateur, est supprimé une fois acquitté, peut être rejeté individuellement, retardé, mis au rebut ; la file se vide. Kafka conserve des **faits** : chaque groupe lit tout, à son rythme, et peut relire le passé ; on ne rejette pas un message, on avance ou non son offset, et un message qui échoue bloque sa partition. Envoyer un SMS de confirmation est une tâche ; « un rendez-vous a été pris », lu par la facturation, les statistiques et les notifications, est un fait. Le module te fait mesurer les deux sur le même cas avant d'écrire la décision (ADR-0270).

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6, [`annexes/versions-bloc-G.md`](../../../annexes/versions-bloc-G.md)) | CloudNativePG **1.30.1** (déjà installé) ; PostgreSQL **18.6** ; PgBouncer : celui de l'image du Pooler (à relever) ; RabbitMQ **4.3.7** (image `registry.par1.medisphere.internal/dockerhub/library/rabbitmq:4.3.7-management`) ; Cluster Operator **2.23.1** ; Messaging Topology Operator **1.20.4** ; Flyway **13.11.1** (image `flyway/flyway:13.11.1`, JRE 25) ; Valkey **9.1.2** (`valkey/valkey:9.1.2-trixie`) ; exportateur `oliver006/redis_exporter` **v1.95.0** ; Strimzi **1.3.0** (chart `strimzi-kafka-operator` 1.3.0) ; Kafka **4.3.1** ; client Python `confluent-kafka` **2.16** ; `pika` **1.4** |
| Projet de la plateforme | `plateforme/donnees` (clone `~/src/donnees`) ; Applications `rabbitmq-operateurs`, `rabbitmq`, `rabbitmq-topologie`, `kafka-essai` (E09-E10) dans `plateforme/gitops/plateforme/` |
| PostgreSQL de MédiAgenda | Cluster `mediagenda-db` : recette dans `plateforme/k8s/espaces/mediagenda-recette/50-mediagenda-db.yaml`, prod rendue par `components/dependances` de `mediagenda/deploiement` (+ `overlays/prod/base-openbao.yaml`) ; Pooler **`mediagenda-db-pooler-rw`** au même endroit que la base de chaque environnement |
| RabbitMQ | grappe **`rabbitmq`**, espace **`messagerie`**, opérateurs dans **`rabbitmq-system`** ; Services `rabbitmq` (AMQPS **5671**, gestion 15672, Prometheus 15692) et `rabbitmq-nodes` ; certificat `rabbitmq-tls` (ClusterIssuer `openbao-services`) ; interface **`https://rabbitmq.apps.par1.medisphere.internal`** (client Keycloak `rabbitmq`) ; compte de bris de glace : Secret `messagerie/rabbitmq-default-user` |
| Topologie (par environnement `<env>`) | vhost `medinotif-<env>` ; échange `notifications` (direct) → file quorum `notifications` ; échange `notifications.rebut` (fanout) → file quorum `notifications.rebut` ; politique `notifications-rebut` (rebut, limite de livraison) ; utilisateurs `medinotif-<env>` (lecture de `notifications`), `mediagenda-<env>` (écriture sur l'échange `notifications`), `wb-checks` (étiquette `monitoring`, aucune permission sur les messages) |
| Secrets OpenBao | `kv/medinotif/<env>/amqp`, `kv/mediagenda/<env>/amqp` (clés `utilisateur`, `mot_de_passe`, `url`) ; `kv/mediagenda/<env>/valkey` (E07) ; `kv/plateforme/rabbitmq/wb-checks` |
| MédiNotif | dépôt `medinotif/deploiement` (clone `~/src/medinotif-deploiement`), AppProject `medinotif`, ApplicationSet **`medinotif`** (`plateforme/gitops/applications/medinotif.yaml`), espaces `medinotif-recette` (E04) et `medinotif-prod` (E08), Deployment `medinotif`, ExternalSecret `medinotif-amqp`, image signée `registry.par1.medisphere.internal/medisphere/medinotif-worker` par empreinte |
| Migrations | image `registry.par1.medisphere.internal/medisphere/mediagenda-migrations:vX.Y.Z` (construite par la CI de `mediagenda/api`) ; Job **`mediagenda-migrations`** (hook Sync, vague −1) ; table d'historique `flyway_schema_history` ; l'ancienne table `mediagenda_historique_schema` reste, en lecture seule |
| Valkey | StatefulSet `valkey` des espaces MédiAgenda (component `valkey` de `mediagenda/deploiement`, E07), utilisateurs ACL `mediagenda`, `exportateur`, `sonde` et `admin` (bris de glace, Secret `valkey-admin`) ; `rediss://` ; `maxmemory` + `allkeys-lru` |
| Kafka (temporaire) | espace `kafka-essai`, `Kafka` `kafka-essai`, `KafkaNodePool` `double-role` (3 nœuds), écouteur `tls` 9093 (TLS + SCRAM-SHA-512), *topics* `rendez-vous.evenements` et `notifications.rebut`, `KafkaUser` `medinotif` et `mediagenda` |
| Vérifications | ClusterRole agrégée **`wb-checks-services`** (E02) ; `~/.config/workbook/rabbitmq-checks.env` (E03) ; fonction `rabbitmq_api` de `lab/lib/check-lib.sh` |
| Documentation | `docs/donnees/` : `postgresql.md` (E02), `rabbitmq.md` (E03), `messagerie-topologie.md` (E04), `migrations.md` (E05, E06), `valkey.md` (E07), `kafka-essai.md` (E09), `comparatif-messagerie.md` (E10), `runbooks/RB-270-postgresql-maintenance-bascule.md` et `runbooks/RB-271-rabbitmq-redemarrage-roulement.md` (E12) |
| Tickets | `PLAT-28xx`, `DEV-28xx`, `CHG-28xx`, `SEC-28xx`, `INC-54xx` (`xx` = numéro d'exercice) |
| Brouillons | `~/m27/eXX/` sur `adm01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte (GitLab, cluster, Argo CD) |
| `<NOEUD-REPLIQUE>` | Le travailleur qui porte une réplique (pas le primaire) de `mediagenda-db` au moment d'E02 |
| `<VERSION-API>` | La version de MédiAgenda en cours (`vX.Y.Z`, étiquette de `mediagenda/api`) |
| `<VERSION-MEDINOTIF>` | La version de l'image de MédiNotif publiée et signée (`vX.Y.Z`) |

### Variables de `lab/lab.env`

Le bloc G a ajouté `WB_RABBITMQ_URL` et `WB_RABBITMQ_CHECKS_FILE` (lues par `rabbitmq_api`). Le module ajoute ses variables, toutes facultatives (les valeurs ci-dessous sont les défauts) :

```
#WB_M27_TRAVAIL="$HOME/m27"                             # brouillons et mesures des exercices
#WB_M27_ENV_RECETTE=recette WB_M27_ENV_PROD=prod       # suffixes des espaces et des vhosts
#WB_M27_DOC_DONNEES="docs/donnees"                     # dossier de documentation dans plateforme/medisphere
#WB_M27_VERSION_RABBITMQ="4.3"                         # mineure attendue de la grappe (4.4 après M27-E15)
#WB_M27_VALKEY_VERSION="9.1"                           # mineure attendue de Valkey (E07)
#WB_M27_PROJET_DONNEES="plateforme/donnees"            # projet GitLab de la plateforme de données
#WB_M27_PROJET_MEDINOTIF_DEPLOIEMENT="medinotif/deploiement"
#WB_M27_PROJET_API="mediagenda/api"
```

Fichiers de `~/.config/workbook/` utilisés : `k8s-checks.kubeconfig` (M14), `gitlab-checks.token` (M01), `grafana-checks.token` (M21, pour les requêtes Prometheus), `openbao-checks.env` (M25), et **`rabbitmq-checks.env`** (E03, 600 : `RABBITMQ_USER=wb-checks`, `RABBITMQ_PASSWORD=…`).

---

## Règles du module

1. **Les bases de données ne se « réparent » pas en supprimant.** Jamais de `kubectl delete pvc`, jamais de suppression d'objets dans `cnpg-k8s-par1`, jamais de `kubectl delete cluster` sur un environnement qui compte. Avant toute intervention en `mediagenda-prod` : une sauvegarde `Completed` de moins d'une heure (`kubectl cnpg backup`, M16).
2. **Les messages sont des données de santé.** Un SMS de rappel contient un numéro de téléphone et une date de rendez-vous. Pas de copie de message dans un ticket ou un dépôt ; le compte `wb-checks` ne lit **aucun** message ; tes messages d'essai utilisent des valeurs **factices** (`+33600000000`, `@exemple.fr`).
3. **On ne purge pas une file pour « débloquer ».** Une file pleine est un symptôme (consommateur arrêté, rebut qui boucle) : on cherche la cause, on n'efface pas les messages.
4. **Une migration publiée ne se modifie pas.** Erreur dans `V3__…` déjà appliqué quelque part ? On écrit `V5__…`. `flyway repair` n'est pas un outil de confort (E05).
5. **Les essais sont temporaires et un à la fois** : Kafka (E09-E10) est retiré à la fin d'E10, avant tout autre essai ; les grappes jetables vont dans `wb-essais`.
6. **Pas de vérification TLS désactivée** (`--insecure`, `verify_none`, `sslmode=require` « pour que ça marche »). AMQPS, `rediss://` et PostgreSQL vérifient le certificat **et** le nom du serveur.
7. **Aucune image ni chart Bitnami**, même « juste pour essayer » : le catalogue gratuit est figé depuis août 2025 (annexe des versions).

### Mémoire : le bilan avant d'installer

Profil du bloc G : socle v5 + `ceph-par1` + `k8s-par1` (travailleurs à 10 Go) ≈ **111 Go** sur les 128 Go de `pve01`. Le module ajoute surtout des pods dans les travailleurs, pas de VM (sauf trois VMs de 1 Go en E13). Ce qui compte, c'est ce que l'ordonnanceur a déjà **réservé** (`requests`) sur chaque travailleur, pas l'utilisation instantanée :

```
admin@adm01:~$ kubectl describe nodes -l '!node-role.kubernetes.io/control-plane' | grep -A8 'Allocated resources'
admin@adm01:~$ kubectl get pods -A -o json | jq -r '
    [.items[] | select(.status.phase == "Running") | {n: .spec.nodeName,
      m: ([.spec.containers[].resources.requests.memory // "0"] | join(","))}] | group_by(.n)[]
    | "\(.[0].n)\t\(length) pods"'
```

Ce que le module va demander (requêtes mémoire, ordres de grandeur à vérifier dans tes rendus) :

| Ajout | Requêtes mémoire | Quand |
|---|---|---|
| Opérateurs RabbitMQ (Cluster Operator 500 Mio, Topology Operator 128 Mio) | ≈ 0,6 Gio | E03, permanent |
| Grappe `rabbitmq` (3 × 1 Gio) | 3 Gio | E03, permanent |
| Pooler (2 pods × 2 environnements) | ≈ 0,3 Gio | E02, permanent |
| MédiNotif (recette, prod) | ≈ 0,3 Gio | E04, E08, permanent |
| Exportateur Valkey (par instance) | ≈ 0,1 Gio | E07, permanent |
| **Kafka `kafka-essai`** (3 nœuds × 1 Gio + opérateurs) | **≈ 4,5 Gio** | E09 → fin d'E10, **retiré** |

> ⚠️ **Kafka est gourmand.** Un courtier Kafka est une JVM : son tas (`-Xms`/`-Xmx`) s'ajoute au cache de pages du système dont il dépend pour être rapide. Avec trois nœuds aux deux rôles, l'essai réserve ≈ 4,5 Gio dans des travailleurs qui en ont 10 chacun et portent déjà la supervision, les journaux, les traces et la base. Avant E09 : relève les requêtes par nœud (commande ci-dessus), vérifie qu'il reste au moins 2 Gio **réservables** sur chaque travailleur, et arrête ce qui ne sert pas (essais des modules précédents dans `wb-essais`). Si un pod Kafka reste `Pending` (`Insufficient memory`), **ne baisse pas** les requêtes de la base ou de RabbitMQ pour lui faire de la place : réduis la taille de l'essai (E09 dit comment) ou libère des réservations inutiles.

---

## Préparer `adm01` et le lab

Vérifie l'état d'entrée :

```
admin@adm01:~$ lab/bin/check 26 46        # mini-projet du M26 : durcissement-v1
admin@adm01:~$ lab/bin/check 25 46        # secrets-v1 : OpenBao, ESO, identifiants dynamiques
admin@adm01:~$ kubectl get nodes          # six nœuds Ready, v1.36.x
admin@adm01:~$ kubectl -n argocd get applications | grep -v 'Synced *Healthy'
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette | head -30
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

Les deux premiers contrôles doivent être verts et l'avant-dernière commande ne doit lister que l'en-tête. Le statut de `mediagenda-db` doit montrer trois instances, un primaire, la réplication synchrone et un archivage des WAL sans erreur (`Continuous Backup status`). Il te faut quelques Go libres sur `pve01` en plus du profil.

Retrouve dans ton dépôt `plateforme/k8s` et dans `mediagenda/deploiement` où sont définis aujourd'hui `mediagenda-db` (recette, prod) et le StatefulSet `valkey` (dev, recette, prod), et note-le dans `~/m27/preparation.md` : plusieurs exercices les modifient, et l'endroit compte (recette par `plateforme/k8s`, prod par Argo CD).

Outils sur `adm01` :

```
admin@adm01:~$ kubectl cnpg version                     # plugin du M16, même mineure que l'opérateur (1.30)
admin@adm01:~$ bao version && bao token lookup >/dev/null && echo "session OpenBao ouverte"
admin@adm01:~$ uv --version && jq --version && yq --version
```

Crée le projet GitLab `plateforme/donnees` (vide, branche `main` protégée, fusion par MR, comme les autres projets de la plateforme) et clone-le dans `~/src/donnees`. Le jeton de déploiement en lecture d'Argo CD pour le groupe `plateforme` (identifiant `repo-creds-plateforme`, M20) couvre déjà ce nouveau projet.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 27 <XX>`. Elles sont en lecture seule : objets du cluster par le compte `wb-checks` (jamais les Secrets), API de gestion de RabbitMQ par `wb-checks` (métadonnées : files, politiques, connexions — jamais les messages), Applications d'Argo CD, fichiers sur `main` par l'API de GitLab, métriques par Prometheus, métadonnées d'OpenBao par l'AppRole `wb-checks`.
- Certains contrôles portent sur un **état récent** (un message passé par le rebut, une connexion par le pooler dans les 15 dernières minutes) : si un contrôle est rouge juste après une modification, refais l'action de l'exercice puis relance.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M27-EXX/` : `donnees/` reproduit `plateforme/donnees`, `k8s/` `plateforme/k8s`, `gitops/` `plateforme/gitops`, `secrets/` `plateforme/secrets`, `identite/` `plateforme/identite`, `mediagenda-api/` et `medinotif-worker/` les dépôts de code (correctifs `git apply`), `mediagenda-deploiement/` et `medinotif-deploiement/` les dépôts de déploiement, `medisphere/` la documentation.

## Ordre conseillé

```
Palier 1 :  E01 ─ E02 ─ E03 ─ E04 ─ E05
Palier 2 :  E06 ─ E07 ─ E08 ─ E09 ─ E10 ─ E11 ─ E12
Palier 3 :  E13 ─ E14 ─ E15 ─ E16 ─ E17 ─ E18
Palier 4 :  E19 ─ E20 ─ E21 ─ E22 ─ E23 ─ E24
Palier 5 :  E25 (mini-projet)
```

1. **E01** — positionnement, à froid.
2. **E02** en premier : il crée la ClusterRole `wb-checks-services`, sans laquelle les vérifications de RabbitMQ et de Kafka ne voient rien.
3. **E03 → E04** dans l'ordre strict (grappe, puis topologie et MédiNotif) ; **E05** est indépendant de la messagerie.
4. **E06** après E05 (Flyway) ; **E08** après E04 et E06 (MédiAgenda publie ce que E06 a rendu possible : le contact du patient) ; **E07** quand tu veux dans le palier.
5. **E09 → E10** d'une traite : l'essai Kafka est retiré à la fin d'E10, et rien d'autre de lourd ne tourne en même temps.
6. **E11** et **E12** pour finir le palier.
7. Paliers 3 à 5 : voir leurs fichiers.

Durée indicative : palier 1, 8 à 10 heures ; palier 2, 12 à 15 heures ; palier 3, 10 à 12 heures ; palier 4, 6 à 8 heures ; mini-projet, 4 à 6 heures.

## Pour aller plus loin

- CloudNativePG 1.30 : rôles déclaratifs <https://cloudnative-pg.io/docs/1.30/declarative_role_management> · bases déclaratives <https://cloudnative-pg.io/docs/1.30/declarative_database_management> · *pooler* <https://cloudnative-pg.io/docs/1.30/connection_pooling> · mises à jour progressives <https://cloudnative-pg.io/docs/1.30/rolling_update> · greffon `kubectl cnpg` <https://cloudnative-pg.io/docs/1.30/kubectl-plugin>
- PgBouncer, modes et limites : <https://www.pgbouncer.org/features.html>
- Flyway : concepts <https://documentation.red-gate.com/flyway/flyway-concepts> · paramètres <https://documentation.red-gate.com/flyway/reference/configuration>
- Valkey : ACL <https://valkey.io/topics/acl/> · TLS <https://valkey.io/topics/tls/> · éviction <https://valkey.io/topics/lru-cache/>
- RabbitMQ : files quorum <https://www.rabbitmq.com/docs/quorum-queues> · confirmations <https://www.rabbitmq.com/docs/confirms> · rebut <https://www.rabbitmq.com/docs/dlx> · Khepri <https://www.rabbitmq.com/docs/metadata-store> · opérateurs Kubernetes <https://www.rabbitmq.com/kubernetes/operator/operator-overview>
- Strimzi 1.3 : <https://strimzi.io/docs/operators/latest/deploying> · Kafka, garanties de livraison : <https://kafka.apache.org/documentation/#semantics>
- Fiche NATS : [`annexes/decouverte/nats.md`](../../../annexes/decouverte/nats.md)
