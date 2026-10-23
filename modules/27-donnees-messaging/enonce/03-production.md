# Module 27 — Palier 3 : Production

Les paliers 1 et 2 ont posé les briques : CloudNativePG approfondi (rôles et bases déclaratifs, *pooler* PgBouncer), RabbitMQ par ses opérateurs avec une topologie déclarative, MédiNotif en recette puis en production, Flyway et des migrations *expand/contract*, Valkey 9 durci, Kafka essayé puis retiré. Il manque ce qui en fait des services de production. Claire Morel veut une comparaison honnête avec **Patroni**, la référence hors Kubernetes, avant de graver CloudNativePG dans un ADR. Nadia Roussel veut des **alertes** qui la réveillent pour de bonnes raisons et un **plan de reprise** qui a déjà été joué une fois. Karim Benali veut des **chiffres** : combien de connexions le *pooler* économise, combien de messages par seconde la grappe RabbitMQ tient avec des confirmations. Et il faut décider, par écrit, de la montée en RabbitMQ 4.4. Le palier se termine par l'ADR-0270 et un questionnaire de production.

Prérequis : paliers 1 et 2 du module (`lab/bin/check 27 02` à `27 10` verts) ; M16 (CloudNativePG, plugin Barman Cloud, `ObjectStore` `cnpg-s3`), M20 (Argo CD), M21 (kube-prometheus-stack, Grafana, conventions de règles et de tableaux), M25 (OpenBao, ESO), M05/M13 (OpenTofu, module `vm-debian`), M04 (Ansible).

> **Rappels du module** (introduction) : toute modification passe par le code et Argo CD. Données et messagerie dans `plateforme/donnees` (`rabbitmq/`, `topologie/`, `outils/`) ; espaces, quotas et bases de recette dans `plateforme/k8s/espaces/` ; règles et tableaux dans `plateforme/observabilite` ; applications dans `mediagenda/deploiement` et `medinotif/deploiement`. Les secrets ne sont jamais dans Git : OpenBao (`kv/…`) et ESO. Tout nouveau flux réseau va dans la matrice (`docs/socle/matrice-flux.md`, `docs/kubernetes/reseau/matrice-flux-cluster.md`) et dans `group_vars/role_routeur/pare_feu.yml`. La documentation de ce module vit dans `docs/donnees/` de `plateforme/medisphere` (`adr/`, `runbooks/` ; ce palier prend les runbooks à partir de **RB-274**).

> ⚠️ **Mémoire** : ce palier crée trois VMs Patroni (3 × 1 Go) le temps de M27-E13, une grappe RabbitMQ jetable dans `wb-essais` en M27-E15 et M27-E16 (≈ 1,5 Gi), et une base d'essai. Jamais deux composants temporaires à la fois (PLAN §4.13) : détruis chaque essai avant de passer au suivant, et vérifie la marge des travailleurs avant (`kubectl top nodes`, tableau « nœuds » du M21).

## État d'entrée du palier 3

Ce que les paliers 1 et 2 ont laissé, et que ce palier suppose. Si un nom diffère chez toi, adapte **ton** dépôt au nom ci-dessous ou note l'écart : les contrôles et les pannes du palier 4 utilisent ces noms.

| Élément | Nom et emplacement | Exercice |
|---|---|---|
| Base de MédiAgenda | `Cluster` CNPG **`mediagenda-db`** dans `mediagenda-recette` (`plateforme/k8s/espaces/mediagenda-recette/50-mediagenda-db.yaml`, `task appliquer`) et `mediagenda-prod` (rendu par `components/dependances` de `mediagenda/deploiement`, corrigé par `overlays/prod/`) ; 3 instances, réplication synchrone `method: any`, `number: 1`, `dataDurability: required` ; `pg_stat_statements` ; archivage par le plugin Barman Cloud (`ObjectStore` **`cnpg-s3`**) en recette depuis M16-E19 — pour la prod, M27-E15 le vérifie | M16, M25, E02 |
| Rôles et bases | rôles gérés (`spec.managed.roles`) dont `mediagenda_api` (groupe des comptes dynamiques d'OpenBao `mediagenda-api-<env>`), `openbao`, et en recette `mediagenda_lecture` / `lucas_lecture` ; compte de migration dynamique `mediagenda-migrateur-<env>` ; CRD `Database` `mediagenda-db-mediagenda` (`databaseReclaimPolicy: retain`) | M25, E02 |
| *Pooler* | `Pooler` **`mediagenda-db-pooler-rw`** (type `rw`, mode `transaction`, 2 instances, PgBouncer 1.26.1 épinglé, métriques 9127, PodMonitor du component `supervision`) en recette et en prod ; l'URL de l'API (ExternalSecret `mediagenda-db-api` du component `identifiants-dynamiques`) vise le *pooler*, celle du migrateur `mediagenda-db-rw` | E02 |
| Lecture des CRD par les checks | ClusterRole agrégée **`wb-checks-services`** (`rabbitmq.com`, `kafka.strimzi.io` ; CNPG déjà lisible par `wb-checks-stockage`) | E02 |
| Opérateurs RabbitMQ | Cluster Operator 2.23.1 et Messaging Topology Operator 1.20.4, espace **`rabbitmq-system`**, manifestes dans `plateforme/donnees/vendor/rabbitmq/` ; Application `rabbitmq-operateurs` | E03 |
| Grappe RabbitMQ | `RabbitmqCluster` **`rabbitmq`**, espace **`messagerie`**, 3 nœuds, RabbitMQ **4.3.7**, certificat `rabbitmq-tls` (`openbao-services`), AMQPS 5671 dans le cluster, plugin Prometheus (15692), CiliumNetworkPolicy `rabbitmq` (`rabbitmq/reseau.yaml`), interface `https://rabbitmq.apps.par1.medisphere.internal` (client Keycloak `rabbitmq`) ; Secret `rabbitmq-default-user` = bris de glace ; utilisateur `wb-checks` (`kv/plateforme/rabbitmq/wb-checks`) ; Application `rabbitmq` | E03 |
| Topologie | `plateforme/donnees/topologie/medinotif-{recette,prod}/` (Application `rabbitmq-topologie`) : vhosts **`medinotif-recette`**, **`medinotif-prod`** ; échange `notifications` (direct) ; file quorum **`notifications`** ; échange (fanout) et file quorum **`notifications.rebut`** ; politique `notifications-rebut` (`delivery-limit: 5`, `dead-letter-strategy: at-least-once`, `overflow: reject-publish`) ; utilisateurs **`medinotif-<env>`** (lecture de `notifications`), **`mediagenda-<env>`** (écriture sur l'échange `notifications`), permission vide de **`wb-checks`** (étiquette `monitoring`) | E04, E08 |
| MédiNotif | dépôt **`medinotif/deploiement`** (`base/`, `overlays/recette`, `overlays/prod` : 2 réplicas, PDB), ApplicationSet **`medinotif`** (prod synchronisée à la main), espaces **`medinotif-recette`**, **`medinotif-prod`**, Deployment **`medinotif`**, ExternalSecret `medinotif-amqp` (`kv/medinotif/<env>/amqp`), métriques 9100 (`medinotif_messages_total{resultat}`) | E04, E08 |
| MédiAgenda publie | component `notifications` de `mediagenda/deploiement` (ExternalSecret `mediagenda-amqp` → `MEDIAGENDA_AMQP_URL`, NetworkPolicy vers `messagerie`), racine MédiSphère par le component `racine-medisphere` ; échange `notifications`, confirmations de publication, `mandatory` ; métrique `mediagenda_notifications_total{resultat}` (`publiee`, `echec`, `desactivee`) ; une publication ratée ne fait pas échouer la requête | E07, E08 |
| Migrations | image `registry.par1.medisphere.internal/medisphere/mediagenda-migrations:vX.Y.Z` (Flyway 13.11.1 Community), Job hook **`mediagenda-migrations`** (Sync, vague −1, conteneur `flyway`, connexion directe à `mediagenda-db-rw`), table `flyway_schema_history`, `baseline` à 2 ; `V3__rappel_expand` (`canal_rappel` NOT NULL DEFAULT `'aucun'`, `contact_rappel`, contraintes `NOT VALID`, `lock_timeout` 5 s) et `V4__rappel_contract` (contraintes validées, défaut retiré) : **V4 est la dernière migration** | E05, E06 |
| Valkey | component **`valkey`** de `mediagenda/deploiement` dans les trois overlays : StatefulSet **`valkey`** en 9.1.2, conteneurs `valkey` et `exportateur` (9121), TLS seul (`valkey-tls`, `openbao-services`), fichier ACL (`default` désactivé ; utilisateurs `mediagenda`, `exportateur`, `sonde`, `admin` de bris de glace), `maxmemory` + `allkeys-lru`, `tls-auto-reload-interval 3600` ; Secrets `valkey-comptes`, `valkey-admin` (clé `mot_de_passe`), `mediagenda-valkey` (clé `url`) ; `kv/mediagenda/<env>/valkey` | E07 |
| Kafka | **retiré** à la fin de M27-E10 (Application, espace `kafka-essai`, PVC, CRD) ; comparaison écrite `docs/donnees/comparatif-messagerie.md` | E09, E10 |
| Runbooks | RB-270 (maintenance et bascule de PostgreSQL) et, facultatif, RB-271 (redémarrage de RabbitMQ par roulement) ; RB-272 et RB-273 restent libres | E12 |

---

### M27-E13 — Patroni sur VMs : l'autre façon de faire  `LAB` `★★★`

> **Ticket PLAT-2813** — *De : Claire Morel*
> Avant de signer l'ADR des données, je veux qu'on ait fait tourner **Patroni**, que tous nos candidats DBA connaissent et que l'ancien prestataire utilisait ailleurs. Trois VMs jetables, PostgreSQL 18 et etcd sur les mêmes machines, une bascule planifiée, une bascule sur panne, le mode maintenance. Puis une comparaison écrite avec CloudNativePG, et on détruit tout. Une journée, pas plus.

**Objectifs pédagogiques**
- Monter une grappe Patroni 4.1 avec etcd comme magasin de configuration distribué (DCS) sur trois VMs Debian 13.
- Pratiquer `patronictl` : `list`, `switchover`, `failover`, `pause`/`resume`, `edit-config`, `history`.
- Comprendre ce que CloudNativePG fait à la place de Patroni (élection, clôture de l'ancien primaire, point d'accès), et ce qu'il ne fait pas.

**Prérequis** : M05 (OpenTofu, état chiffré), M13-E02 (module `vm-debian`), M04 (Ansible), M16-E25 (bascules CNPG), M27-E12 (runbook de bascule).
**Durée indicative** : 2 h 30.

**Contexte technique**
- VMs **`pg-patroni01`**, **`pg-patroni02`**, **`pg-patroni03`** : VMID **2271-2273**, VNet `vsandbox`, adresses fixes **10.10.99.71-73**, 1 vCPU, 1 Go, Debian 13, étiquettes `env-m27` et `role-pg-essai` (à créer dans NetBox). Code dans **`plateforme/infra`**, configuration racine `envs/m27/`, état OpenTofu **`m27`** (clé `envs/m27/terraform.tfstate`), module `vm-debian` de `plateforme/tofu-modules` (dernière étiquette publiée).
- PostgreSQL **18** du dépôt PGDG (`apt.postgresql.org`), **Patroni 4.1.5** (PyPI, dans un environnement virtuel, ou PGDG si la version y est), etcd du paquet Debian 13 (`etcd-server`, API v3, section `etcd3` de Patroni). Configuration par Ansible : projet `plateforme/donnees`, dossier **`patroni-essai/`**.
- Ports : 5432 (PostgreSQL), 8008 (API REST de Patroni), 2379-2380 (etcd), tous dans le même VLAN (aucune règle de bordure pour eux) ; depuis `adm01`, SSH comme pour toute VM de `vsandbox`.
- Patroni n'offre **pas** de point d'accès stable : il faut un HAProxy qui interroge l'API REST (`GET /primary` répond 200 sur le primaire seulement) ou vip-manager (adresse flottante pilotée par la clé du *leader* dans etcd).

**Travail demandé**
1. Dans `plateforme/infra`, crée `envs/m27/` sur le modèle de `envs/m13/` (état distant à part, chiffré) et déclare les trois VMs par `vm-debian` avec leurs enregistrements DNS. `tofu plan`, relis, `tofu apply`.
2. Dans `plateforme/donnees/patroni-essai/`, écris l'inventaire et le *playbook* qui installent etcd (grappe de trois membres, `initial-cluster-state new`), PostgreSQL 18 (sans la grappe créée par défaut par le paquet Debian), Patroni 4.1.5 et son unité systemd, avec une configuration par nœud (`scope: pg-essai`, API REST, `etcd3`, `bootstrap.dcs` avec `synchronous_mode: true`, `pg_hba`, comptes de réplication et de *rewind*). Les mots de passe ne sont pas dans Git (Vault Ansible `lab`).
3. Démarre, puis montre la grappe : `patronictl list` et `patronictl topology`. Où sont stockés le *leader*, la configuration commune, l'état des membres ? Lis-les directement dans etcd (`etcdctl get --prefix`).
4. **Bascule planifiée** : `patronictl switchover` vers un réplica choisi. Mesure l'indisponibilité en écriture vue d'un client (une boucle d'`INSERT` toutes les 200 ms depuis une des VMs, par l'API REST qui désigne le primaire, ou par un HAProxy que tu poses sur `pg-patroni01`).
5. **Bascule sur panne** : arrête brutalement le primaire (`systemctl kill -s SIGKILL patroni` puis PostgreSQL, ou coupe sa carte réseau dans Proxmox). Mesure le temps jusqu'au nouveau primaire, compare-le à `ttl` et `loop_wait`, et observe le retour de l'ancien (`pg_rewind`). Essaie aussi `patronictl failover` sur une grappe saine : que se passe-t-il, et pourquoi la documentation conseille `switchover` ?
6. **Mode maintenance** : `patronictl pause`, arrête PostgreSQL sur le primaire : que fait Patroni ? `patronictl resume`.
7. Rédige `docs/donnees/comparatif-patroni-cnpg.md` : architecture (DCS, élection, clôture de l'ancien primaire, point d'accès), opérations (bascule, mise à jour mineure et majeure, sauvegarde et restauration, ajout d'un nœud), supervision, sécurité, ce qu'il faudrait construire autour de Patroni pour arriver au niveau de service de CNPG chez MédiSphère, **mesures** (indisponibilité en `switchover` et en panne, des deux côtés : reprends celles de M16-E25 pour CNPG), et une conclusion.
8. **Détruis** l'essai : `tofu destroy` de `envs/m27` (l'état reste, vide), puis vérifie qu'il ne reste ni VM, ni enregistrement DNS, ni objet NetBox. Garde le code dans Git.

**Critères de réussite**
- [ ] `envs/m27/` existe dans `plateforme/infra` (VMID 2271-2273, `vsandbox`, 10.10.99.71-73) et `patroni-essai/` dans `plateforme/donnees`.
- [ ] `comparatif-patroni-cnpg.md` est publié : sortie de `patronictl list` à trois membres, temps de bascule mesurés des deux côtés, conclusion.
- [ ] Les VMs 2271-2273 n'existent plus, ni dans Proxmox, ni dans NetBox, ni dans le DNS.

**Vérification** : `lab/bin/check 27 13` (à lancer **après** la destruction : tant que les VMs existent, le contrôle d'absence échoue).

<details><summary>Indice 1</summary>

Le paquet `postgresql-18` de Debian crée et démarre une grappe `18/main` : Patroni veut un répertoire de données qu'il initialise lui-même. `pg_dropcluster --stop 18 main` juste après l'installation, ou `create_main_cluster = false` dans `/etc/postgresql-common/createcluster.conf` **avant** l'installation. Patroni a besoin des binaires : `postgresql.bin_dir: /usr/lib/postgresql/18/bin`.
</details>

<details><summary>Indice 2</summary>

Le *leader* est une clé avec un bail (TTL) dans le DCS : le primaire la renouvelle à chaque boucle (`loop_wait`). Si elle expire (`ttl`), les réplicas font la course pour la prendre, et seul celui qui réussit se promeut. Lis `etcdctl get --prefix /service/pg-essai/ --keys-only` avant et après une bascule. `patronictl history` liste les changements de *timeline*.
</details>

<details><summary>Indice 3</summary>

Pour mesurer l'indisponibilité, horodate chaque `INSERT` réussi côté client et calcule le plus grand trou. En `synchronous_mode`, regarde aussi ce que devient `synchronous_standby_names` quand le réplica synchrone disparaît, et compare avec `dataDurability: required` de CNPG.
</details>

**Pour aller plus loin** : lis dans les notes de version pourquoi le DCS Raft intégré (Patroni sans etcd) est **déprécié** et pourquoi on ne le choisirait pas aujourd'hui. Essaie `synchronous_mode: quorum` et compare avec `method: any` de CNPG. Regarde comment l'opérateur Zalando « Postgres Operator » utilise Patroni **dans** Kubernetes (le DCS devient l'API Kubernetes).

---

### M27-E14 — Superviser les données et la messagerie  `LAB` `★★★`

> **Ticket PLAT-2814** — *De : Nadia Roussel*
> On a trois nouveaux services de production et je ne vois rien. Je veux savoir **avant** Julien qu'un réplica PostgreSQL décroche, que le primaire a disparu, qu'une file de notifications grossit ou n'a plus de consommateur, que RabbitMQ a levé une alarme mémoire ou disque, que le cache est plein. Un tableau de bord par service, des alertes avec un runbook derrière, et pas d'alerte qui sonne pour rien.

**Objectifs pédagogiques**
- Collecter les métriques du *pooler* PgBouncer, de RabbitMQ (agrégées et par objet) et de Valkey sans exploser la cardinalité.
- Écrire des règles d'alerte sur des symptômes et des causes utiles à l'astreinte, avec des seuils et des durées justifiés.
- Provisionner un tableau de bord par le code et lier chaque alerte à un runbook.

**Prérequis** : M21-E07 (PodMonitor de `mediagenda-db`), M21-E14/E15 (conventions de règles et d'alertes), M21-E17/E19 (tableaux provisionnés), M27-E02 (*pooler*), M27-E03 (plugin Prometheus), M27-E07 (exportateur Valkey).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Le plugin `rabbitmq_prometheus` sert trois points d'accès sur 15692 : `/metrics` (agrégé par défaut, préfixe `rabbitmq_`), `/metrics/per-object` (tout, par objet : coûteux) et `/metrics/detailed?family=…&vhost=…` (préfixe `rabbitmq_detailed_`, seulement les familles et vhosts demandés). Les alarmes : `rabbitmq_alarms_memory_used_watermark`, `rabbitmq_alarms_free_disk_space_watermark`.
- Le *pooler* CNPG expose ses métriques (préfixe `cnpg_pgbouncer_`, dont `cnpg_pgbouncer_pools_cl_waiting`, `cnpg_pgbouncer_pools_sv_active`, `cnpg_pgbouncer_pools_maxwait`) sur le port nommé `metrics` (9127). L'option `spec.monitoring.enablePodMonitor` du `Pooler` et du `Cluster` est **dépréciée** en 1.30 : écris tes PodMonitor.
- CNPG publie déjà, par le PodMonitor du M21 : `cnpg_collector_up`, `cnpg_pg_replication_lag`, `cnpg_pg_replication_streaming_replicas`, `cnpg_pg_replication_in_recovery`, `cnpg_collector_sync_replicas`, `cnpg_backends_waiting_total`, `cnpg_pg_stat_replication_replay_lag_seconds`.
- Conventions du M21 : PrometheusRule dans `plateforme/observabilite/regles/` (étiquette `medisphere.internal/supervision: "oui"`), étiquettes `gravite` et `equipe`, annotations `resume`, `description`, `runbook_url` ; tableaux dans `tableaux/` (ConfigMaps générées, dossier Grafana par annotation).

**Travail demandé**
1. **RabbitMQ** : dans `plateforme/donnees/rabbitmq/`, ajoute un ServiceMonitor (ou PodMonitor) qui collecte `/metrics` **et** `/metrics/detailed` limité aux familles `queue_coarse_metrics` et `queue_consumer_count` des vhosts `medinotif-recette` et `medinotif-prod`. Pourquoi pas `/metrics/per-object` ? Vérifie que la politique réseau de la grappe (M27-E03) laisse entrer Prometheus sur 15692 et que le flux figure dans la matrice du cluster.
2. **Pooler** : vérifie que les métriques du *pooler* arrivent en recette et en prod (PodMonitor de M27-E02) ; sinon, corrige-le. Relève la version de PgBouncer réellement servie (`pgbouncer --version` dans un pod du *pooler*) et compare-la à la 1.26 (trois CVE corrigées).
3. **Valkey** : vérifie que l'exportateur de M27-E07 est collecté (`redis_up`, `redis_memory_used_bytes`, `redis_memory_max_bytes`, `redis_evicted_keys_total`) ; sinon, ajoute son ServiceMonitor ou PodMonitor.
4. **Règles** : `regles/alertes-donnees.yaml` avec au moins : réplication PostgreSQL en retard ; primaire absent (aucune instance hors récupération, ou collecteur muet) ; réplication synchrone dégradée ; clients du *pooler* en attente ; file `notifications` qui grossit ; file sans consommateur ; alarme mémoire ou disque de RabbitMQ ; cache Valkey plein (mémoire au plafond **et** évictions ou refus d'écriture). Justifie chaque seuil et chaque `for:` en commentaire. Passe-les à `promtool check rules` et ajoute des tests unitaires (`promtool test rules`) pour deux d'entre elles.
5. **Tableau** : « Données et messagerie » (UID **`m27-donnees`**, dossier « Plateforme », variable `${datasource}`, variable d'environnement) : PostgreSQL (primaire, réplicas, retard, connexions, attentes), *pooler* (clients actifs et en attente, connexions serveur), RabbitMQ (messages prêts et non acquittés par file, consommateurs, débit de publication et de livraison, alarmes, mémoire et disque libre), Valkey (mémoire, évictions, taux de succès du cache de MédiAgenda).
> ⚠️ **Attention** (étape 6) : arrêter MédiNotif de recette laisse s'accumuler les notifications de recette (rien n'est perdu : elles attendent dans la file quorum) ; isoler un réplica avec `fencing` n'est sûr que pour **un seul** réplica à la fois (`dataDurability: required` : avec deux réplicas isolés, les écritures de la recette se bloquent). Vérifie avant `kubectl cnpg status` (trois instances saines). Retour arrière : MR inverse pour MédiNotif, `kubectl cnpg fencing off`.

6. **Essai** : déclenche **en recette** deux alertes sans rien casser de durable : arrête MédiNotif de recette (MR qui le met à zéro réplica, puis retour) et regarde « file sans consommateur » puis « file qui grossit » passer en *pending* puis *firing* ; isole un réplica de la base de recette avec `kubectl cnpg fencing on` puis `off`. Note les délais réels.
7. Écris **RB-274** « Alertes des données et de la messagerie » (`docs/donnees/runbooks/`) : pour chaque alerte, ce qu'elle veut dire, la première commande à lancer, les causes probables et le geste. Pose le `runbook_url` de chaque alerte.

**Critères de réussite**
- [ ] Séries présentes dans Prometheus : `rabbitmq_detailed_queue_messages_ready` pour les deux vhosts, `rabbitmq_alarms_memory_used_watermark`, `cnpg_pgbouncer_pools_cl_waiting` en recette et en prod, `redis_up` de Valkey.
- [ ] Les huit familles d'alertes existent dans une PrometheusRule, chacune avec `runbook_url` ; `promtool test rules` passe en CI.
- [ ] Le tableau `m27-donnees` est provisionné depuis `tableaux/`.
- [ ] RB-274 publié ; tes mesures de délais d'alerte y figurent.

**Vérification** : `lab/bin/check 27 14`

<details><summary>Indice 1</summary>

Dans un ServiceMonitor, chaque `endpoints[]` peut avoir son `path` et ses `params` (une table de listes : `params: {family: [queue_coarse_metrics, queue_consumer_count], vhost: [medinotif-recette, medinotif-prod]}`). Regarde le nom du port Prometheus dans le Service `rabbitmq` créé par l'opérateur (`kubectl -n messagerie get svc rabbitmq -o yaml`).
</details>

<details><summary>Indice 2</summary>

« Primaire absent » ne se dit pas « `cnpg_pg_replication_in_recovery == 0` est absent » : une métrique qui disparaît avec son pod ne déclenche rien. Compte les instances qui répondent **et** ne sont pas en récupération, par cluster : `count by (namespace) (cnpg_collector_up == 1 and on (namespace, pod) cnpg_pg_replication_in_recovery == 0)`, et pense à `absent()` ou à une valeur 0 explicite. Pour une file qui « grossit », `deriv()` sur 15 min **et** un plancher absolu évitent de sonner pour trois messages.
</details>

<details><summary>Indice 3</summary>

Un cache plein n'est pas une panne avec `allkeys-lru` : c'est sa vie normale. Ce qui est anormal, c'est un cache plein **qui refuse des écritures** (`noeviction`), ou dont le taux de succès s'effondre parce qu'il évince tout ce qu'il reçoit. Ton alerte doit faire la différence.
</details>

**Pour aller plus loin** : les tableaux de bord officiels de RabbitMQ (« RabbitMQ-Overview », « RabbitMQ-Quorum-Queues-Raft ») sont publiés par l'équipe RabbitMQ : importe-les dans `wb-essais` de Grafana et compare avec le tien. Regarde `pg_stat_statements` par le PodMonitor de CNPG (requêtes personnalisées, `monitoring.customQueriesConfigMap`).

---

### M27-E15 — Reprise et montée de version : réplica de secours, RabbitMQ 4.4  `LAB` `★★★`

> **Ticket PLAT-2815** — *De : Nadia Roussel, en copie Claire Morel*
> Si la base de production disparaît demain (volumes perdus, erreur humaine, Ceph en panne), je veux une copie **déjà démarrée** qui suit la prod depuis le stockage objet, et qu'on ait vérifié qu'on sait la promouvoir — sans jamais toucher à la prod pour l'essai. Même logique pour RabbitMQ : ses définitions (vhosts, files, politiques) doivent être exportées chaque nuit hors du cluster.
>
> **Changement CHG-2815** — *De : Karim Benali*
> RabbitMQ 4.4 est sortie lundi. On répète la montée sur une grappe jetable ; si la répétition passe, on l'applique à `messagerie/rabbitmq`, sinon on écrit pourquoi on reste en 4.3. Attention : c'est un aller simple.

**Objectifs pédagogiques**
- Construire un *standalone replica cluster* CNPG alimenté par l'archive des WAL du plugin Barman Cloud, le superviser, et mesurer le RPO réel d'une reprise depuis le stockage objet.
- Répéter une promotion sans toucher à la source.
- Exporter et réimporter les définitions RabbitMQ ; répéter puis conduire (ou refuser, par écrit) une montée de version mineure irréversible.

**Prérequis** : M16-E19/E24 (`ObjectStore`, restauration), M27-E14 (supervision), M27-E03/E04 (grappe et topologie RabbitMQ), M25 (ESO).
**Durée indicative** : 2 h 30.

**Contexte technique**
- La production archive ses WAL par le plugin Barman Cloud. **Vérifie le `serverName`** sous lequel elle archive dans `s3://cnpg-k8s-par1/` : la recette archive déjà sous `mediagenda-db` (M16-E19). Deux clusters ne peuvent pas archiver sous le même nom. Si la prod n'archive pas encore (le M16 ne l'a fait qu'en recette), ajoute-le d'abord par MR avec `serverName: mediagenda-db-prod` et une sauvegarde de base aussitôt.
- Un *standalone replica cluster* : `spec.replica.enabled: true`, `spec.replica.source` vers un `externalClusters` de type `plugin` (`barmanObjectName`, `serverName`), `bootstrap.recovery.source` vers le même. L'`ObjectStore` est un objet **de l'espace** : il en faut un dans `mediagenda-secours`. Un réplica qui n'est alimenté que par l'archive a un retard au moins égal à l'intervalle d'archivage (`archive_timeout` posé par CNPG).
- `.spec.replica.enabled: false` promeut un réplica autonome : c'est **irréversible**, la copie devient une base indépendante.
- RabbitMQ : `GET /api/definitions` exporte vhosts, files, échanges, liaisons, politiques, utilisateurs (avec l'empreinte de leur mot de passe) et permissions ; `POST /api/definitions/<vhost>` réimporte un vhost. Les utilisateurs et permissions sont déjà dans Git (Topology Operator) et leurs mots de passe dans OpenBao.
- RabbitMQ 4.4 : stockage v2 des files classiques **sans retour** en 4.3 ; la montée par l'opérateur se fait nœud par nœud (changement d'`image`) ; les *feature flags* de la version de départ doivent tous être activés avant (`rabbitmqctl list_feature_flags`) ; `spec.autoEnableAllFeatureFlags` du `RabbitmqCluster` active les nouveaux après la montée. La compatibilité du Cluster Operator 2.23 avec 4.4 n'est pas annoncée : c'est à la répétition de le dire.

**Travail demandé**
1. **Réplica de secours.** Crée l'espace **`mediagenda-secours`** dans `plateforme/k8s/espaces/` (PSA `restricted`, quota, refus réseau par défaut, sortie vers `s3-01` 8333 seulement, sortie DNS) et, dedans, l'`ObjectStore` **`cnpg-s3`** (identité S3 en **lecture seule** si ton stockage le permet : justifie ton choix) et le `Cluster` **`mediagenda-db-secours`** (deux instances, même image que la prod, sans archivage). Applique, attends `Cluster in healthy state`, et vérifie qu'il rejoue les WAL de la prod.
2. **Supervision du secours** : ajoute-le au PodMonitor et une alerte « réplica de secours en retard » (au-delà de deux fois l'intervalle d'archivage) à `alertes-donnees.yaml`.
3. **Répétition de promotion, sans toucher la prod.** Dans `wb-essais`, crée une seconde copie (`secours-essai`, une instance) alimentée par la même archive, attends qu'elle rattrape, puis **promeus-la**. Mesure le RPO : écart entre `pg_last_xact_replay_timestamp()` au moment de la promotion et l'heure de la dernière écriture connue de la prod ; puis force `pg_switch_wal()` sur la prod juste avant la promotion et mesure de nouveau. Supprime l'essai (volumes compris) dès la mesure faite : il contient des **données de santé**.
4. Écris **RB-275** « Reprendre MédiAgenda sur le réplica de secours » : quand le déclencher (et qui décide), les étapes (promotion, pointer le *pooler* — `spec.cluster` d'un `Pooler` est **immuable** —, archivage sous un **nouveau** `serverName`, sauvegarde aussitôt), le RPO et le RTO mesurés, le retour arrière (il n'y en a pas : pourquoi), la restauration des définitions RabbitMQ.
5. **Définitions RabbitMQ.** Dans `plateforme/donnees/rabbitmq/sauvegarde-definitions/`, un CronJob nocturne exporte les définitions de la grappe **sans les empreintes de mots de passe** et les dépose sur `s3-01`, compartiment **`messagerie-definitions`** (identité dédiée par ESO, rétention 30 jours). Lance-le une fois à la main (`kubectl create job --from=cronjob/…`), relis le fichier, puis réimporte le vhost `medinotif-recette` exporté dans un vhost d'essai de la grappe jetable de l'étape 6.
6. **Répétition de la montée 4.3 → 4.4.** Dans `wb-essais`, une grappe jetable **`rabbitmq-essai`** (3 nœuds, ressources réduites) en **même version 4.3.x que la prod**, avec la topologie de recette réimportée et des messages dans une file quorum et une file classique. Vérifie les *feature flags*, monte en 4.4.0 par l'opérateur, observe la montée nœud par nœud (files quorum : leader, membres), vérifie qu'aucun message n'est perdu, essaie de **redescendre** en 4.3 et note ce qui se passe. Supprime la grappe jetable.
> ⚠️ **Attention** (étape 7) : la montée de `messagerie/rabbitmq` en 4.4 est **irréversible** (stockage v2 des files classiques, *feature flags*) et touche la grappe partagée par la recette **et la production**. Ne l'applique qu'après une répétition réussie, en fenêtre annoncée, définitions exportées juste avant ; il n'y a pas de retour arrière en 4.3 autre qu'une grappe neuve et le réimport des définitions (les messages en file seraient perdus).

7. **Décision.** Écris `docs/donnees/montee-rabbitmq-4.4.md` : ce que la répétition a montré, la décision (appliquer ou rester en 4.3 jusqu'à une date), et, si tu appliques : MR sur `plateforme/donnees/rabbitmq/` en fenêtre annoncée (CHG-2815), export des définitions juste avant, suivi des files quorum pendant la montée, contrôle après.

**Critères de réussite**
- [ ] `mediagenda-db-secours` est un réplica autonome sain dans `mediagenda-secours`, alimenté par l'archive, sans archivage propre, avec un retard inférieur à 15 min ; une alerte le surveille.
- [ ] Aucune copie d'essai ne reste dans `wb-essais` (ni `Cluster`, ni `RabbitmqCluster`, ni PVC).
- [ ] Le CronJob d'export des définitions a réussi dans les dernières 26 h.
- [ ] La grappe `messagerie/rabbitmq` tourne en 4.3.x **ou** 4.4.x, et `montee-rabbitmq-4.4.md` dit laquelle et pourquoi ; RB-275 contient le RPO mesuré.

**Vérification** : `lab/bin/check 27 15`

<details><summary>Indice 1</summary>

Le plugin Barman Cloud lit l'archive sous `<destinationPath>/<serverName>/`. Le `serverName` du réplica (paramètre de l'`externalClusters`) est celui de la **source**, pas le sien. Ne mets pas de bloc `plugins` avec `isWALArchiver: true` sur le réplica : le jour de sa promotion, il archiverait… où ?
</details>

<details><summary>Indice 2</summary>

`kubectl cnpg status mediagenda-db-secours -n mediagenda-secours` montre le mode réplica et la source ; dans le pod, `SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();`. Côté prod, `SELECT pg_current_wal_lsn(), now();`. Le paramètre `archive_timeout` vu dans `SHOW archive_timeout;` sur le primaire de la prod explique la plus grande partie du RPO.
</details>

<details><summary>Indice 3</summary>

Pour la grappe jetable : `spec.resources` réduites (le défaut de l'opérateur réserve 2 Gi par nœud), `persistence.storage` de 1 Gi, `spec.image` en `registry.par1.medisphere.internal/dockerhub/library/rabbitmq:4.3.<z>-management`. Avant de changer l'image : `rabbitmqctl list_feature_flags name state` sur chaque nœud, et `rabbitmq-queues check_if_node_is_quorum_critical`.
</details>

**Pour aller plus loin** : passe le réplica de secours en **topologie distribuée** (`replica.primary`, `replica.source`, jeton de rétrogradation `demotionToken`) : quelles conditions faudrait-il réunir pour une bascule contrôlée sans reconstruire l'ancienne prod ? Pour RabbitMQ, regarde la *schema definition sync* (fonction commerciale) et ce qu'apporterait une fédération ou un *shovel* vers un second site.

---

### M27-E16 — Performance et dimensionnement : pgbench, perf-test, *pooler*  `LAB` `★★★`

> **Ticket PLAT-2816** — *De : Karim Benali*
> On dimensionne au doigt mouillé. Je veux savoir ce que le *pooler* nous fait gagner (et perdre), combien de messages par seconde RabbitMQ tient **avec** les garanties qu'on a choisies (files quorum, confirmations, `prefetch` à 1), et ce que ça donne pour la rentrée de janvier, quand Julien ouvre MédiAgenda à 40 centres de plus. Mesures dans `wb-essais`, jamais sur la prod.

**Objectifs pédagogiques**
- Mesurer avec `pgbench` l'effet d'un *pooler* en mode transaction : connexions serveur, latence, coût de l'établissement des connexions.
- Mesurer avec `rabbitmq-perf-test` le débit et la latence d'une file quorum, et l'effet des confirmations de publication et du `prefetch`.
- Rédiger un dimensionnement chiffré, avec ses hypothèses et ses limites.

**Prérequis** : M27-E02 (*pooler*), M27-E14 (tableau `m27-donnees`), M16-E28 (mesures de performances de Ceph).
**Durée indicative** : 2 h.

**Contexte technique**
- Banc PostgreSQL : un `Cluster` **`bench-essai`** (une instance, mêmes ressources et même classe de stockage qu'une instance de `mediagenda-db`) et un `Pooler` **`bench-essai-pooler-rw`** (mode `transaction`) dans `wb-essais`. `kubectl cnpg pgbench` crée un Job qui vise le Service `-rw` du cluster ; pour passer par le *pooler*, écris ton Job avec l'image PostgreSQL de CNPG (elle contient `pgbench`).
- `pgbench` : `-i -s` (initialisation), `-c` (clients), `-j` (fils), `-T` (durée), `-C` (une connexion par transaction), `-S` (lecture seule), `-P` (progression), `-M` (protocole).
- `rabbitmq-perf-test` 2.25 : image `pivotalrabbitmq/perf-test` par le cache Harbor (`registry.par1.medisphere.internal/dockerhub/pivotalrabbitmq/perf-test:2.25.0`). Options : `--uri`, `-x`/`-y` (producteurs, consommateurs), `--quorum-queue` (`-qq`), `-u` (file), `-c` (confirmations en vol, `-1` = sans), `-q` (`prefetch`), `-s` (taille), `-r` (débit visé), `-z` (durée), `-f persistent`, `--auto-delete false`.
- Grappe RabbitMQ de banc : le manifeste de `rabbitmq-essai` (M27-E15), mais avec les ressources de la grappe de production (pas celles, réduites, de l'essai de montée) pour que les chiffres vaillent pour elle ; détruite après la mesure.

**Travail demandé**
1. Déploie le banc PostgreSQL (manifestes dans `plateforme/donnees/outils/banc/`), initialise à l'échelle 20.
2. Mesure, 60 s chaque fois, **en direct puis par le *pooler*** : `-c 20` ; `-c 80` (au-delà de `max_connections` ?) ; `-c 20 -C`. Relève TPS, latence moyenne et p95 (`--log` ou `-P`), connexions côté PostgreSQL (`pg_stat_activity`) et côté *pooler* (`SHOW POOLS`, ou le tableau `m27-donnees`). Explique chaque écart.
3. Essaie une transaction **interactive** de MédiAgenda typique (plusieurs requêtes) et une requête préparée côté serveur (`-M prepared`) par le *pooler* en mode transaction : qu'est-ce qui marche, qu'est-ce qui casse, depuis quelle version de PgBouncer, avec quel réglage (`max_prepared_statements`) ?
4. Déploie la grappe RabbitMQ de banc et mesure, 60 s chaque fois, sur une file quorum, messages de 1 Kio persistants : 1 producteur sans confirmation ; avec `-c 1` ; avec `-c 100` ; puis 1 consommateur avec `-q 1` puis `-q 50`, enfin 3 consommateurs. Relève débit et latence (p50, p95, p99).
5. Rapproche des besoins : nombre de rendez-vous par jour et de notifications par rendez-vous (demande les ordres de grandeur à Julien : prends **3 000 rendez-vous par jour aujourd'hui, ×4 en janvier, pointe à 10 % du jour en une heure, 2 notifications par rendez-vous**), connexions de l'API (réplicas × taille de la réserve psycopg) et du Job de migration.
6. Rédige `docs/donnees/dimensionnement.md` : protocole, résultats (tableaux), interprétation, réglages recommandés (`default_pool_size`, `max_client_conn`, `max_connections`, `prefetch` de MédiNotif, nombre de consommateurs), marge pour janvier, limites de la mesure (Ceph partagé, réseau, un seul banc). Supprime le banc (Cluster, Pooler, grappe, Jobs, PVC).

**Critères de réussite**
- [ ] `dimensionnement.md` contient les mesures pgbench (direct et *pooler*, avec et sans `-C`) et perf-test (confirmations, `prefetch`), et une recommandation chiffrée pour janvier.
- [ ] Les manifestes du banc sont dans `plateforme/donnees/outils/banc/`.
- [ ] Le banc est retiré de `wb-essais`.

**Vérification** : `lab/bin/check 27 16`

<details><summary>Indice 1</summary>

Avec `-C`, chaque transaction ouvre une connexion : en direct, c'est un processus PostgreSQL créé et détruit à chaque fois (plus l'échange SCRAM et TLS) ; par le *pooler*, c'est une connexion **client** vers PgBouncer, la connexion serveur restant ouverte. C'est là que l'écart est le plus grand. Sans `-C`, attends-toi au contraire à ce que le *pooler* coûte un peu de latence : pourquoi ?
</details>

<details><summary>Indice 2</summary>

Avec `-c 1`, le producteur attend chaque confirmation avant d'envoyer le message suivant : le débit est borné par la latence d'une écriture répliquée sur la majorité de la file quorum (aller-retour réseau + `fsync`). Avec `-c 100`, il garde 100 messages en vol. MédiAgenda publie un message par requête et attend sa confirmation : laquelle des deux mesures lui ressemble ?
</details>

**Pour aller plus loin** : refais la mesure RabbitMQ pendant que tu arrêtes un nœud de la grappe de banc (`kubectl delete pod`) : que devient la latence p99 au moment de l'élection d'un nouveau leader ? Compare avec la mesure Kafka de M27-E10 si tu l'as notée.

---

### M27-E17 — ADR : données et messagerie de MédiSphère  `RED` `★★`

> **Ticket PLAT-2817** — *De : Claire Morel*
> Le comité d'architecture de jeudi doit trancher, et je ne veux plus rouvrir le débat Kafka tous les mois. Un ADR, avec les options vraiment essayées, les mesures, les licences, et ce qui nous ferait changer d'avis.

**Objectifs pédagogiques**
- Écrire une décision d'architecture fondée sur des essais et des mesures, pas sur des goûts.
- Prendre en compte la licence et la pérennité des outils, pas seulement leurs fonctions.
- Nommer les conditions qui rouvriraient la décision.

**Prérequis** : M27-E09/E10 (Kafka), M27-E13 (Patroni), M27-E05/E06 (Flyway), M27-E16 (mesures), fiche [`annexes/decouverte/nats.md`](../../../annexes/decouverte/nats.md).
**Durée indicative** : 1 h.

**Travail demandé**

Rédige **ADR-0270** « Données et messagerie de MédiSphère » dans `docs/donnees/adr/` (modèle des ADR précédents : contexte, options, décision, conséquences, conditions de révision). Elle couvre quatre décisions liées :
1. **Messagerie** : RabbitMQ (files quorum, accusés, rebut) retenu ; Kafka écarté **pour l'instant** (pourquoi, et quel besoin le ferait revenir) ; NATS JetStream considéré (fiche) et non retenu (pourquoi).
2. **PostgreSQL** : CloudNativePG contre Patroni sur VMs, avec tes mesures de M27-E13.
3. **Migrations** : Flyway Community contre Liquibase 5 et Atlas, **licences comprises** (lis-les : FSL-1.1-ALv2 pour Liquibase depuis 5.0 ; édition Community seulement sous Apache 2.0 pour Atlas).
4. **Cohérence base / messages** : aujourd'hui, MédiAgenda publie après la validation de sa transaction, et une publication ratée est perdue. Décris le motif ***outbox*** (table d'envoi écrite dans la même transaction, relais qui publie) comme évolution, et dis quand il deviendra nécessaire.

**Critères de réussite**
- [ ] ADR-0270 publié dans `docs/donnees/adr/` avec les quatre décisions, des mesures chiffrées et des conditions de révision.
- [ ] Les licences de Flyway, Liquibase et Atlas y sont citées avec leur nom exact.

**Vérification** : `lab/bin/check 27 17` (présence et contenu ; la qualité de l'argumentaire s'évalue avec le corrigé).

<details><summary>Indice</summary>

Une bonne condition de révision est **observable** : « le jour où un deuxième consommateur doit relire l'historique des rendez-vous » plutôt que « si on a besoin de plus de performance ». Pour la licence, cite le fichier `LICENSE` du dépôt à la version utilisée, pas un article de blog.
</details>

---

### M27-E18 — Questions de production : données et messagerie  `Q` `★★★`

> **Ticket PLAT-2818** — *De : Karim Benali*
> Avant de te laisser seul(e) d'astreinte sur ces briques, réponds-moi par écrit. Argumente : « ça dépend » n'est une réponse que si tu dis de quoi.

**Objectifs pédagogiques**
- Raisonner sur les garanties réelles (durabilité, livraison, compatibilité) des briques du module dans des situations d'astreinte.
- Relier chaque réponse à un mécanisme vu dans le module et à un geste d'exploitation.

**Prérequis** : paliers 1 à 3 (M27-E02 à M27-E17).
**Durée indicative** : 45 min. Réponds dans un fichier personnel ; les réponses argumentées sont dans le corrigé.

1. MédiAgenda valide la transaction du rendez-vous, puis publie la demande de notification. Le pod est tué entre les deux. Que se passe-t-il ? Décris deux façons de rendre l'envoi fiable (*outbox* avec relais, capture des changements), leur coût, et pourquoi « publier d'abord, valider ensuite » est pire.
2. RabbitMQ garantit « au moins une fois ». Donne deux situations où MédiNotif reçoit **deux fois** la même demande, puis rends son traitement idempotent : quelle clé, où la stocker, combien de temps, et que faire d'un SMS déjà envoyé ?
3. Avec RabbitMQ 4.3, MédiNotif répond `basic.nack` avec remise en file à un échec passager. Pourquoi la limite de livraison de la file quorum ne protège-t-elle **pas** contre un message qui échoue toujours de cette façon ? Qu'est-ce qui la fait progresser ? Que changerais-tu dans MédiNotif ?
4. La réplication synchrone de `mediagenda-db` est en `dataDurability: required`. Les deux réplicas tombent. Que voit MédiAgenda ? Que voit Nadia ? Quand choisirais-tu `preferred`, et que perdrais-tu ?
5. Décris un *split-brain* PostgreSQL : comment Patroni l'évite-t-il, comment CloudNativePG l'évite-t-il (bail du primaire, contrôle d'isolement, clôture de l'ancien primaire), et dans quel cas restant une écriture validée peut-elle être perdue ?
6. Une partition réseau sépare un nœud RabbitMQ des deux autres. Que deviennent les files quorum dont le leader était sur le nœud isolé ? Les clients connectés à ce nœud ? Les métadonnées (Khepri) ? Qu'est-ce qui a changé par rapport à l'époque de Mnesia et de `cluster_partition_handling` ?
7. Le *pooler* est en mode `transaction`. Cite trois choses que MédiAgenda ne doit pas faire (ou doit faire autrement) dans ce mode, et une raison de garder une connexion directe pour le Job de migration.
8. Un collègue propose le chart Bitnami pour RabbitMQ, « tout le monde l'utilise ». Que réponds-tu, faits datés à l'appui ? Quels risques prend-on en restant sur une image figée ?
9. Comment fait-on une montée **majeure** de PostgreSQL (18 → 19) avec CloudNativePG ? Compare la montée en place (`pg_upgrade` déclenché par `imageName`), l'import logique et la réplication logique : indisponibilité, retour arrière, archive des WAL, statistiques.
10. Une migration Flyway *contract* (`V4__`) supprime une colonne. Le Rollout de MédiAgenda est en *canary* à 20 %. Que se passe-t-il, et comment l'ordre des vagues d'Argo CD et la règle *expand/contract* l'évitent ?
11. Valkey est « un cache » : décris ce que perd MédiAgenda si Valkey disparaît, et trois réglages qui garantissent que sa perte dégrade sans casser (côté serveur et côté client).
12. Le réplica de secours a 7 minutes de retard. La prod brûle. Qui décide la promotion, sur quels éléments, et que dis-tu aux centres de santé sur les rendez-vous pris pendant ces 7 minutes ?

<details><summary>Indice 1</summary>

Pour chaque question, cherche d'abord **où** l'état vit (WAL, journal Raft, DCS, file, base, mémoire d'un processus) et **qui** confirme quoi à qui : la plupart des réponses en découlent.
</details>

<details><summary>Indice 2</summary>

Les exercices qui en parlent : E02, E06, E08 (Q1, Q2, Q7, Q10) ; E04, E20 (Q3) ; E13, E19, E24 (Q4, Q5) ; E15, E24 (Q6, Q12) ; E07, E22 (Q11).
</details>

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions avant d'ouvrir le corrigé, chaque réponse avec son mécanisme et sa conséquence pour MédiSphère.
- [ ] Tu as comparé avec le corrigé et noté les écarts (et l'exercice du module qui les traite).

**Vérification** : pas de script (questions) ; compare avec le corrigé.
