# Module 27 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné : `k8s/` = `plateforme/k8s`, `donnees/` = `plateforme/donnees`, `gitops/` = `plateforme/gitops`, `secrets/` = `plateforme/secrets`, `identite/` = `plateforme/identite`, `politiques/` = `plateforme/politiques`, `mediagenda-api/` = `mediagenda/api`, `mediagenda-deploiement/` = `mediagenda/deploiement`, `medinotif-deploiement/` = `medinotif/deploiement`, `medisphere/` = la documentation. Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie ; un nom en `.extrait` ne contient que ce qui change.

**Ce qui a été vérifié à la rédaction** (23/10/2026) :
- **Manifestes** : tous les objets des corrigés E02 à E05 validés par `kubectl apply --dry-run=server` contre un **kube-apiserver 1.36.2 réel** (binaires *envtest*, etcd) sur lequel on avait chargé les CRD **exactes** des versions retenues : CloudNativePG 1.30.1 (`cnpg-1.30.1.yaml`), plugin Barman Cloud 0.15.1, Cluster Operator 2.23.1 et Messaging Topology Operator 1.20.4 (manifestes de publication), Strimzi 1.3.0, cert-manager 1.21, Gateway API 1.6.1, Argo CD 3.5.5, External Secrets 2.13, Cilium 1.20.3 (CNP, CCNP), prometheus-operator 0.94, Kyverno 1.19.1 (`PolicyException`) ; rendus Kustomize par kubectl 1.36 (Kustomize 5.8.1). Les webhooks des opérateurs ne tournaient pas : leurs validations **propres** (champs immuables, cohérence) ne sont pas couvertes.
- **Opérateurs RabbitMQ** : les deux manifestes téléchargés, leur SHA-256 relevé (`ae35a547…` pour `cluster-operator.yml` v2.23.1, `11a390b0…` pour `messaging-topology-operator-with-certmanager.yaml` v1.20.4) ; `outils/recopier-operateurs.sh` exécuté (téléchargement, vérification, refus d'une empreinte fausse) ; inventaire des objets (le `Namespace rabbitmq-system` est dans les **deux** fichiers) ; rendu Kustomize avec réécriture des images et retrait du doublon ; source de l'opérateur 2.23.1 lue (`internal/resource/statefulset.go`, `configmap.go`, `service.go`) : contexte de sécurité conforme à `restricted`, **aucun PodDisruptionBudget**, écouteurs ajoutés avec TLS (5671, 15671, 15691 en plus de 15672 et 15692), délai d'arrêt par défaut de 604 800 s, `total_memory_available_override_value` calculé depuis la limite.
- **RabbitMQ 4.3.7** réel (image `rabbitmq:4.3.7-management`, conteneur) avec TLS (chaîne racine → intermédiaire → feuille, comme la PKI de services) : Khepri activé (*feature flag* `khepri_db`, `rabbitmq-diagnostics metadata_store_status` existe), files quorum `notifications` et `notifications.rebut`, politique de rebut (dont `dead-letter-strategy: at-least-once` + `overflow: reject-publish`, acceptés et effectifs), permissions des trois comptes ; **un utilisateur `monitoring` sans permission sur un vhost ne voit pas ses files** (`/api/queues/<vhost>` → 404) — d'où la permission vide de `wb-checks` ; lecture d'un message refusée à `wb-checks` (403) ; compte de MédiNotif refusé en écriture sur l'échange ; configuration OAuth 2.0 (`auth_backends`, `auth_oauth2.*`, `management.oauth_*`) acceptée au démarrage, API HTTP toujours accessible en authentification basique.
- **Chaîne d'un message** de bout en bout sur ce RabbitMQ : `ressources/E04-messages/publier.py` (confirmations, `mandatory`, vérification du nom du certificat) → file quorum → **vrai worker MédiNotif** (`apps/medinotif`, `amqps://`, `SSL_CERT_FILE` = racine, `MEDINOTIF_DECLARER_FILE=0`) → messages invalides au rebut avec `x-death` (`reason: rejected`).
- **Flyway 13.11.1** réel (image `flyway/flyway:13.11.1`, en UID 10004, racine en lecture seule) contre **PostgreSQL 18.6** : base amenée en V2 par le **vrai** `python -m mediagenda.migrate` ; `migrate` sans reprise refusé (« non-empty schema… no schema history table ») ; reprise par `baselineOnMigrate` + `baselineVersion=2` (ligne `BASELINE`, `installed_by = mediagenda` grâce au `SET role` du migrateur) ; rappel `beforeBaseline.sql` **exécuté** pendant `baselineOnMigrate` et bloquant sur une base à V1 seule (code 1, aucune table créée) ; base vide → V1, V2 appliquées sans reprise ; `validate` refuse un fichier modifié (somme de contrôle) ; `clean` refusé par défaut ; une variable `FLYWAY_*` inconnue est **ignorée sans message** ; JDBC `sslmode=verify-full&sslrootcert=…` vérifié contre un PostgreSQL TLS (nom faux refusé) ; licence Apache 2.0 lue dans l'image ; `Dockerfile.migrations` construit et essayé.
- **PgBouncer 1.25.1** (image `ghcr.io/cloudnative-pg/pgbouncer`) en mode **transaction** devant PostgreSQL 18 : `max_prepared_statements` = 200 par défaut (`SHOW CONFIG`) ; le dépôt PostgreSQL de MédiAgenda (psycopg 3.3.6, libpq 18.6, `prepare_threshold` 5) a passé 80 requêtes **préparées** sans erreur, et ses tests d'intégration sont verts à travers lui.
- **CloudNativePG** : documentation 1.30.1 lue dans le dépôt à l'étiquette (`docs/src/*.md`) ; source lue pour les Poolers (`pkg/specs/pgbouncer/deployments.go` : étiquettes `cnpg.io/cluster` et `cnpg.io/podRole=pooler`, port nommé `metrics`, conteneur d'initialisation `bootstrap-controller` à l'image de l'**opérateur**, ressources de ce conteneur tirées de `spec.template.spec.resources`) ; dernière image PostgreSQL relevée sur `ghcr.io` (18.6, reconstruction `18.6-202610190957-minimal-trixie`) ; PgBouncer 1.26.1 publié.
- **OpenTofu** : `clients-rabbitmq.tf` validé (`tofu validate`, OpenTofu 1.11, fournisseur `keycloak/keycloak` 5.x téléchargé).
- **Scripts** : checks et `recopier-operateurs.sh` passés à `shellcheck -x` et `bash -n` ; `publier.py` passé à `ruff`.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- tout ce qui demande les opérateurs **en fonctionnement** dans `k8s-par1` : adoption de la base existante par la CRD `Database`, réconciliation des rôles (`validUntil`), redémarrages dus à `pg_stat_statements`, comportement exact des clients du pooler pendant une bascule (durées), drainage des nœuds, création effective de la grappe RabbitMQ et de la topologie par les opérateurs, webhooks ;
- la **connexion du Topology Operator** à l'API de gestion **en TLS** (15671) avec la racine montée dans `/etc/ssl/certs` (programme Go) : si l'opérateur préfère 15672, la CNP le permet aussi ;
- la relecture par RabbitMQ d'un certificat **renouvelé** (72 h) sans redémarrage (cache PEM d'Erlang) : à observer en E03 avec `cmctl renew` ;
- la connexion SSO à l'interface de gestion (chemin exact de la page de rappel de la 4.3 : d'où le joker `https://rabbitmq.apps…/*` dans le client Keycloak) et le contenu réel du jeton (`resource_access.rabbitmq.roles`) ;
- la version de PgBouncer embarquée par défaut dans CloudNativePG 1.30.1 (le corrigé suppose qu'elle est antérieure à 1.26.1 et l'épingle) ;
- Kyverno : refus du Pooler de prod sans l'extension de l'exception `cnpg-operateur-sans-condense` (déduit de la source de CNPG et de la politique du M26, pas observé).

---

### M27-E01 — Test de positionnement : données et messagerie

**Barème** : 2 points par question. 2 = complet et justifié (pour un QCM : bonne réponse **et** les autres options écartées avec leur raison) ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 24. En dessous de 12, relis les « Concepts clés » de l'introduction avant E02. Les questions 1 à 4 sont reprises en E02, E12 et M27-E24 ; 5 à 7 en E05, E06 et M27-E21 ; 8 en E07 et M27-E22 ; 9 à 12 en E03, E04, E08, E10 et M27-E20.

**Réponses argumentées — PostgreSQL et CloudNativePG**

**1. Réplication synchrone `any 1`, `dataDurability: required`.** Au `COMMIT`, le primaire écrit son WAL, l'envoie aux réplicas, et ne rend la main à l'application que quand **au moins une** des réplicas listées a confirmé l'avoir écrit (`synchronous_commit` à `on` : écrit et vidé sur disque). Une transaction confirmée existe donc sur deux machines : la perte du primaire ne la perd pas. Si les **deux** réplicas sont injoignables, avec `required` le primaire **attend** : les `COMMIT` restent bloqués (les lectures continuent), jusqu'au retour d'une réplica — on préfère l'indisponibilité en écriture à la perte de données. Avec `preferred`, CloudNativePG retire les réplicas absentes de la liste synchrone : les écritures continuent, mais une transaction confirmée pendant ce temps n'existe que sur le primaire (perte possible s'il meurt à ce moment). C'est le compromis de M27-E19 (écritures bloquées) et M27-E24.

**2. Réponse B.** La bascule planifiée choisit une réplique **synchrone et à jour** au moment où tout va bien, se vérifie (`kubectl cnpg status`), et ne coûte que quelques secondes sans écriture ; ensuite le drainage n'évince que des réplicas. Notons que CloudNativePG protège déjà le primaire : son PodDisruptionBudget retient l'éviction et l'opérateur fait une bascule **avant** le drainage (documentation 1.30, « Kubernetes upgrade ») — un `drain` normal ne serait donc pas catastrophique, mais tu ne choisis ni le moment ni la cible. A est dangereux : `--disable-eviction` contourne les PodDisruptionBudgets (suppression directe) et `--force` supprime les pods non gérés : le primaire est tué, c'est un **failover** (subi, avec la détection et la promotion à attendre) au lieu d'une bascule. C tue aussi le primaire (même effet). D est absurde : réduire à une instance supprime deux réplicas (et leurs données à reconstruire) et laisse un seul exemplaire des données au pire moment.

**3. `max_connections` à 1 000.** Chaque connexion est un processus avec sa mémoire (`work_mem` par opération de tri, catalogue en cache…) ; `max_connections` dimensionne aussi des structures partagées (verrous, instantanés) : au-delà de quelques centaines, le coût de gestion des connexions **actives** (contention des verrous internes, calcul des instantanés MVCC) dégrade tout le serveur, même si la plupart sont inactives. Et le nombre de connexions utiles en parallèle est de l'ordre du nombre de cœurs. Il faut changer le **nombre de clients** vus par PostgreSQL : une réserve de connexions (PgBouncer, le Pooler de CNPG) qui fait passer des centaines de clients sur quelques dizaines de connexions serveur, plus des réserves applicatives bornées (psycopg-pool `max_size`) et des délais.

**4. Réponse C.** `pg_advisory_lock` prend un verrou de **session** : en mode transaction, la connexion serveur qui le porte retourne dans la réserve à la fin de l'instruction, et les requêtes suivantes du même client partent sur une **autre** connexion — le travail n'est plus protégé, et le verrou reste pris par une connexion que d'autres clients réutilisent. A et B fonctionnent (une instruction seule est une transaction implicite ; un `BEGIN … COMMIT` garde sa connexion jusqu'au `COMMIT`). D n'est pas un problème du mode transaction : PgBouncer tient une réserve par couple (base, utilisateur), c'est un problème de **taille** de réserves (une réserve par utilisateur, d'où les comptes dynamiques qui doublent les réserves pendant leur recouvrement). Flyway prend justement un verrou consultatif : les migrations ne passent pas par le pooler.

**Réponses argumentées — migrations de schéma**

**5. Migrations et canary.** (a) **Dangereuse** : l'ancienne version, qui ne nomme pas la colonne à l'insertion, échoue (`NOT NULL` sans défaut). Version sûre : colonne facultative ou avec un défaut **constant** (instantané depuis PostgreSQL 11), et `NOT NULL` plus tard. (b) **Dangereuse** : l'ancienne version lit et écrit `motif`, qui n'existe plus → erreurs immédiates. Version sûre : *expand* (ajouter `raison`, écrire dans les deux, copier l'existant), nouvelle version qui lit `raison`, puis *contract* (supprimer `motif`). (c) **Sans danger** : l'ancienne version l'ignore. (d) **Dangereuse** pendant le canary : la nouvelle version ne l'utilise plus mais l'**ancienne**, qui sert encore 90 % du trafic, si. On la supprime seulement quand plus aucune ancienne version ne tourne (et après le délai de retour arrière). Règle générale : le schéma de la version N+1 doit servir la version N.

**6. Le verrou qui gèle.** `ALTER TABLE` demande un verrou `ACCESS EXCLUSIVE`, incompatible avec tout, même un `SELECT`. S'il est en concurrence avec une transaction longue (un rapport, une session `psql` oubliée), il **attend** ; et toutes les requêtes arrivées après lui attendent **derrière** lui dans la file des verrous : l'API est gelée tant que la transaction longue n'a pas fini, alors que l'`ALTER` lui-même ne durerait que quelques millisecondes. `SET lock_timeout = '5s'` (et `statement_timeout`) dans la migration la fait **échouer vite** au lieu d'attendre ; le Job de migration doit alors réessayer (`backoffLimit`), et l'échec arrête la synchronisation **avant** la nouvelle version — l'ancienne continue de servir (M27-E06, M27-E21).

**7. Une migration publiée modifiée.** Flyway compare la somme de contrôle (CRC32) du fichier à celle de `flyway_schema_history` : `validate` (lancé par défaut avant `migrate`) **échoue** (« Migration checksum mismatch for migration version 3 ») et rien n'est appliqué ; le déploiement s'arrête. La bonne correction : remettre le fichier `V3__` **à l'identique** et écrire une migration `V5__` qui corrige l'effet de la faute. `flyway repair` réaligne les sommes de contrôle : il fait taire l'erreur sans corriger la base, et les environnements divergent (la recette a la V3 fautive, une base neuve aura la V3 corrigée).

**Réponse argumentée — cache**

**8. Réponse B.** `allkeys-lru` évince, parmi **toutes** les clés, celles lues le moins récemment : exactement ce qu'on attend d'un cache (les créneaux d'un jour que personne ne consulte partent d'abord). A (`noeviction`) refuse les écritures quand la mémoire est pleine : le cache cesse d'être rempli, l'API dégrade (erreurs d'écriture, journal plein d'avertissements). C (`volatile-ttl`) n'évince que les clés **avec** une durée de vie, en commençant par celles qui expirent le plus tôt : nos clés ont toutes un TTL, ça marcherait, mais une clé sans TTL (erreur de code, autre usage) ne serait jamais évincée et le choix « bientôt expirée » est moins pertinent que « peu lue ». D : sans `maxmemory`, Valkey grossit jusqu'à la limite du conteneur et le noyau le **tue** (OOMKilled) : perte de tout le cache, redémarrage, et pendant ce temps `/pret` de MédiAgenda passe en 503.

**Réponses argumentées — messagerie**

**9. Files quorum.** Trois répliques, majorité 2 : la perte d'**un** nœud ne perd rien et n'empêche pas la publication (le leader est réélu parmi les deux restants si c'était lui). Deux nœuds perdus : plus de majorité, la file est **indisponible** (pas de perte de ce qui était confirmé, mais plus de publication ni de consommation) jusqu'au retour d'un nœud. À deux nœuds, la majorité est… deux : la perte d'un seul nœud bloque tout — deux nœuds sont **moins** disponibles qu'un seul pour Raft (et Khepri, les métadonnées, a la même règle). Toujours un nombre **impair** (3, 5). Les files miroir classiques ont été **supprimées en RabbitMQ 4.0** : une déclaration `ha-mode` est ignorée/refusée, il faut des files quorum (ou des *streams*).

**10. Au moins une fois.** Le worker reçoit le message, envoie le SMS, puis **meurt** (OOM, nœud perdu, `SIGKILL` après le délai de grâce) avant que l'`ack` n'arrive au courtier : le message non acquitté retourne dans la file, un autre worker l'envoie **une seconde fois**. Pour l'éviter : un consommateur **idempotent** — un identifiant de message stable (`message_id` posé par l'éditeur, ou la clé métier `rendez_vous_id` + `modele`) enregistré **avec** l'envoi (table « déjà envoyé », contrainte unique) et vérifié avant d'envoyer ; à défaut, le fournisseur de SMS dédoublonne par une clé d'idempotence. Les **confirmations de publication** garantissent à l'éditeur que le courtier a **pris en charge** le message (écrit sur une majorité pour une file quorum) ; avec `mandatory`, qu'il a été **routé** vers une file. Elles ne garantissent ni qu'il sera consommé, ni qu'il ne sera pas dupliqué (une confirmation perdue → republication → doublon), ni rien sur le traitement.

**11. Kafka ou RabbitMQ.** (a) **RabbitMQ** : une tâche par rendez-vous, un seul consommateur doit la faire, acquittée individuellement, rejetée au rebut si invalide ; la file se vide. (b) **Kafka** : des **faits** conservés 30 jours, relus indépendamment par plusieurs groupes (facturation, statistiques, recommandations) à leur rythme, y compris un nouveau consommateur qui relit l'historique : c'est un journal, pas une file. (c) **RabbitMQ** : réessai différé d'**un** message sans bloquer les autres (TTL + rebut vers la file d'origine, ou greffon de messages différés) ; avec Kafka, un message qui échoue bloque sa partition (l'ordre est la promesse), il faudrait une chaîne de *topics* de réessai gérée par l'application.

**12. La boucle de rejet.** Côté RabbitMQ : rejeter **sans** remise en file (`basic_nack(requeue=False)`) un message invalide — ce que fait MédiNotif pour `INVALIDE` — l'envoie vers l'échange de rebut (*dead letter exchange*) de la file s'il y en a un ; et la **limite de livraison** des files quorum (`delivery-limit`, politique) envoie au rebut un message dont la livraison a échoué trop de fois (RabbitMQ 4.3 compte `basic.reject` et le consommateur qui meurt avant l'accusé ; un `basic.nack` avec remise en file est un « retour » qui ne compte pas). Kafka n'a ni rejet ni rebut : le consommateur avance ou non son offset. Pour sortir un message empoisonné, l'**application** doit le recopier dans un *topic* de rebut puis valider l'offset (ce que fait le backend Kafka de MédiNotif en E10) ; sinon, soit elle le saute (perte), soit elle bloque la partition.

---

### M27-E02 — CloudNativePG en profondeur : rôles, bases et *pooler*

**Solution**

Fichiers : `plateforme/k8s` : [`rbac/wb-checks-services.yaml`](fichiers/M27-E02/k8s/rbac/wb-checks-services.yaml), [`50-mediagenda-db.yaml`](fichiers/M27-E02/k8s/espaces/mediagenda-recette/50-mediagenda-db.yaml), [`52-lecture-lucas.yaml`](fichiers/M27-E02/k8s/espaces/mediagenda-recette/52-lecture-lucas.yaml), [`55-mediagenda-db-base.yaml`](fichiers/M27-E02/k8s/espaces/mediagenda-recette/55-mediagenda-db-base.yaml), [`56-mediagenda-db-pooler.yaml`](fichiers/M27-E02/k8s/espaces/mediagenda-recette/56-mediagenda-db-pooler.yaml), [`sql/preparer-lecture.sql`](fichiers/M27-E02/k8s/espaces/mediagenda-recette/sql/preparer-lecture.sql), [`collecte-prometheus.yaml`](fichiers/M27-E02/k8s/composants/reseau/politiques/collecte-prometheus.yaml) ; `mediagenda/deploiement` : [`externalsecrets.yaml`](fichiers/M27-E02/mediagenda-deploiement/components/identifiants-dynamiques/externalsecrets.yaml), [`podmonitor-pooler.yaml`](fichiers/M27-E02/mediagenda-deploiement/components/supervision/podmonitor-pooler.yaml), prod : [`pooler.yaml`](fichiers/M27-E02/mediagenda-deploiement/overlays/prod/pooler.yaml), [`base-pg-stat-statements.yaml`](fichiers/M27-E02/mediagenda-deploiement/overlays/prod/base-pg-stat-statements.yaml), [extrait de `kustomization.yaml`](fichiers/M27-E02/mediagenda-deploiement/overlays/prod/kustomization.extrait-E02.yaml) ; `plateforme/politiques` : [exception étendue](fichiers/M27-E02/politiques/kyverno/exceptions/cnpg-operateur-sans-condense.yaml) ; essais : [`essai-maj.yaml`](fichiers/M27-E02/essais/essai-maj.yaml), [`journal-maintenance.md`](fichiers/M27-E02/essais/journal-maintenance.md) ; [`docs/donnees/postgresql.md`](fichiers/M27-E02/medisphere/docs/donnees/postgresql.md).

*A. Droits des vérifications.*

1. `wb-checks-stockage` (M16-E10) donne déjà `postgresql.cnpg.io/*` et `barmancloud.cnpg.io/*` : **aucune** CRD de CloudNativePG ne manque (Pooler, Database, DatabaseRole compris). `wb-checks-services` ajoute `rabbitmq.com` et `kafka.strimzi.io`/`core.strimzi.io`, rien d'autre. Ces CRD ne contiennent pas de mot de passe (les `User` et `KafkaUser` **référencent** un Secret).
   ```
   admin@adm01:~/src/k8s$ task appliquer
   admin@adm01:~$ kubectl auth can-i list queues.rabbitmq.com -A --as=system:serviceaccount:wb-system:wb-checks
   yes
   admin@adm01:~$ kubectl auth can-i get secrets -n messagerie --as=system:serviceaccount:wb-system:wb-checks
   no
   ```
   L'agrégation est faite par le contrôleur de `kube-controller-manager` en quelques secondes : `kubectl get clusterrole wb-checks -o yaml | grep rabbitmq` montre la règle recopiée.

*B. Rôles et base.*

2. Réponses de la documentation 1.30 (« Declarative role management ») : un rôle **absent** de `managed.roles` (et de toute `DatabaseRole`) est **ignoré** — l'opérateur ne le supprime pas (« ignores roles that exist in the database but are not included ») ; une appartenance absente de `inRoles` est **révoquée** ; une `connectionLimit` omise revient à `-1`. Le mot de passe vient d'un Secret `kubernetes.io/basic-auth` (`username` = nom du rôle, `password`) référencé par `passwordSecret` ; l'opérateur l'encode en **SCRAM-SHA-256 de son côté** avant le `CREATE/ALTER ROLE` (le texte clair ne transite pas dans le journal de PostgreSQL) ; un Secret étiqueté `cnpg.io/reload: "true"` est appliqué aussitôt qu'il change.
3. [`50-mediagenda-db.yaml`](fichiers/M27-E02/k8s/espaces/mediagenda-recette/50-mediagenda-db.yaml) (blocs « M27-E02 ») et [`52-lecture-lucas.yaml`](fichiers/M27-E02/k8s/espaces/mediagenda-recette/52-lecture-lucas.yaml). Le mot de passe est écrit dans OpenBao sans passer par l'historique (`bao kv put … password=@/dev/shm/mdp`, puis `shred`). Après `task appliquer` :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette get cluster mediagenda-db -o jsonpath='{.status.managedRolesStatus}' | jq
   admin@adm01:~/src/k8s$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -v ON_ERROR_STOP=1 \
       < espaces/mediagenda-recette/sql/preparer-lecture.sql
   admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -c \
       "SELECT rolname, rolcanlogin, rolconnlimit, rolvaliduntil FROM pg_roles WHERE rolname LIKE '%lecture%'"
   ```
   `managedRolesStatus.byStatus.reconciled` contient les deux nouveaux rôles ; `rolvaliduntil` porte la date. À l'échéance, PostgreSQL **refuse l'authentification par mot de passe** (les sessions déjà ouvertes continuent : `VALID UNTIL` porte sur le mot de passe). La MR suivante passe `ensure: absent` (le rôle est supprimé ; s'il possédait des objets, `DROP ROLE` échoue et l'opérateur le signale dans le statut), puis retire le bloc.
4. [`55-mediagenda-db-base.yaml`](fichiers/M27-E02/k8s/espaces/mediagenda-recette/55-mediagenda-db-base.yaml) : `databaseReclaimPolicy: retain` (c'est le défaut, on l'écrit pour qu'aucune relecture ne le change par mégarde ; `delete` exécuterait `DROP DATABASE` à la suppression de l'objet). `status.applied: true` et aucun `CREATE DATABASE` dans le journal du primaire : la base existante est prise en charge, seuls les écarts sont appliqués.
5. Le paramètre `pg_stat_statements.max` (ou `.track`) suffit : l'opérateur ajoute la bibliothèque à `shared_preload_libraries` **et** crée l'extension dans chaque base. Changer `shared_preload_libraries` exige un **redémarrage** : les trois instances redémarrent, réplicas d'abord, puis bascule et ancien primaire (`primaryUpdateMethod: switchover`). Lecture (avec `mediagenda_lecture`, qui a `pg_read_all_stats`, ou en superutilisateur par `kubectl cnpg psql`) : requête de [`postgresql.md`](fichiers/M27-E02/medisphere/docs/donnees/postgresql.md). Chez MédiAgenda, on trouve en tête l'insertion d'un rendez-vous, la liste triée par date et le calcul des créneaux (`SELECT debut FROM rendez_vous WHERE …`) ; le texte est normalisé (`$1`, `$2`) : pas de donnée de santé dans la vue.

*C. Le pooler.*

6. CloudNativePG crée et gère le rôle `cnpg_pooler_pgbouncer` (authentification par certificat) que PgBouncer utilise pour son `auth_query` : tout rôle PostgreSQL avec un mot de passe peut se connecter **à travers** le pooler, les comptes dynamiques d'OpenBao compris. PgBouncer suit les instructions préparées **au niveau du protocole** depuis 1.21 (`max_prepared_statements`, 200 par défaut depuis 1.24 — vérifié sur 1.25.1) ; psycopg 3.2+ les accepte à travers PgBouncer ≥ 1.22 si la libpq est ≥ 17 (psycopg-binary 3.3.6 embarque libpq 18.6) : MédiAgenda garde `prepare_threshold` par défaut (vérifié : 80 requêtes préparées sans erreur). Ne passent **jamais** par lui : ce qui dépend de la session — verrou consultatif de **session** (Flyway), `SET` sans `LOCAL`, `LISTEN/NOTIFY`, tables temporaires, curseurs `WITH HOLD` — et les sessions d'administration.
7. [`56-mediagenda-db-pooler.yaml`](fichiers/M27-E02/k8s/espaces/mediagenda-recette/56-mediagenda-db-pooler.yaml). Le conteneur s'appelle obligatoirement `pgbouncer` pour être fusionné avec celui de l'opérateur. Version réelle :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette get pooler mediagenda-db-pooler-rw -o jsonpath='{.status.image}{"\n"}'
   admin@adm01:~$ kubectl -n mediagenda-recette exec deploy/mediagenda-db-pooler-rw -c pgbouncer -- pgbouncer --version
   ```
   La dernière corrective publiée par CloudNativePG au 23/10 est **1.26.1** (la 1.26 corrige trois CVE) : on l'épingle par `spec.pgbouncer.image`, étiquette **et** empreinte, depuis le cache `ghcr`. Les ressources déclarées sur le conteneur `pgbouncer` ne sont **pas** recopiées sur le conteneur d'initialisation `bootstrap-controller` (l'opérateur lui donne `spec.template.spec.resources`, au niveau du pod) : c'est la `LimitRange` de l'espace qui lui donne des valeurs, ce qui satisfait la règle Kyverno `exiger-limites`.
8. Les pods du pooler portent `cnpg.io/cluster: mediagenda-db` : ils héritent de `postgresql-sortie` (API Kubernetes, instances), de `postgresql-entree` (opérateur) et de `mediagenda-acces-base` (entrée depuis l'API, port 5432 — le pooler écoute sur 5432) ; la sortie de l'API vers `cnpg.io/cluster` (politique du chart) les couvre aussi. Il ne manque que la collecte de Prometheus sur **9127** : port ajouté à la politique de cluster [`collecte-prometheus`](fichiers/M27-E02/k8s/composants/reseau/politiques/collecte-prometheus.yaml).
9. [`podmonitor-pooler.yaml`](fichiers/M27-E02/mediagenda-deploiement/components/supervision/podmonitor-pooler.yaml), dans le component `supervision` (tous les environnements ; en dev il ne sélectionne rien). `enablePodMonitor` du Pooler (comme celui du Cluster) est marqué **déprécié** dans la CRD 1.30.1 (« will be removed in an upcoming release »).
10. Le modèle de l'ExternalSecret `mediagenda-db-api` fabrique l'URL : hôte `mediagenda-db-pooler-rw` ([fichier](fichiers/M27-E02/mediagenda-deploiement/components/identifiants-dynamiques/externalsecrets.yaml)) ; celui du migrateur garde `mediagenda-db-rw`. Le Secret change → Reloader redémarre le Rollout (M25-E15). Preuve :
    ```
    admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -c \
        "SELECT usename, client_addr, application_name, count(*) FROM pg_stat_activity WHERE usename LIKE 'v-%' GROUP BY 1,2,3"
    admin@adm01:~$ kubectl -n mediagenda-recette exec deploy/mediagenda-db-pooler-rw -c pgbouncer -- psql -c 'SHOW POOLS;'
    ```
    Les connexions des comptes `v-…-mediagenda-api-…` viennent désormais des adresses des **pods du pooler** ; `SHOW POOLS` montre la base `mediagenda` et les comptes dynamiques ; dans Prometheus, `cnpg_pgbouncer_stats_total_xact_count{database="mediagenda"}` croît.

*D. Maintenance.* Démarche et mesures dans [`journal-maintenance.md`](fichiers/M27-E02/essais/journal-maintenance.md).

11. `kubectl cnpg promote mediagenda-db mediagenda-db-2 -n mediagenda-recette` : l'opérateur arrête proprement l'ancien primaire (*fast shutdown*, WAL envoyé), promeut la cible, reconfigure l'ancien en réplique. Quelques secondes sans écriture. Côté pooler : les connexions serveur vers l'ancien primaire sont coupées, PgBouncer se reconnecte au Service `-rw` (qui pointe déjà sur le nouveau) ; les clients voient quelques erreurs (`server conn crashed?`, `SSL connection has been closed unexpectedly`) sur les transactions **en cours** à ce moment, puis tout repart **sans** redémarrer l'API (psycopg-pool écarte les connexions mortes).
12. Drainage d'un nœud de réplique : l'instance évincée reste `Pending` (trois travailleurs, anti-affinité **requise**, les deux autres en portent déjà une) jusqu'à `uncordon`, puis revient sur son PVC et rattrape par la réplication ; le PDB des réplicas n'en laisse partir qu'une à la fois. Nœud du **primaire** : le PDB du primaire retient l'éviction, l'opérateur fait d'abord une **bascule**, puis l'ancien primaire (devenu réplique) est évincé.
13. Image reconstruite par empreinte : l'opérateur met à jour les **réplicas** une par une (redémarrage sur la nouvelle image), puis fait une **bascule** vers une réplique à jour et redémarre l'ancien primaire en dernier (`primaryUpdateStrategy: unsupervised`, `primaryUpdateMethod: switchover`). Avec `supervised`, il s'arrêterait avant la bascule et attendrait un `kubectl cnpg promote` humain — intéressant en prod. Montée 18.4 → 18.6 sur [`essai-maj`](fichiers/M27-E02/essais/essai-maj.yaml) : même séquence ; une montée **mineure** de PostgreSQL ne change pas le format des données, d'où ce simple remplacement d'image (une montée **majeure** demanderait `pg_upgrade` ou une réplication logique).

*E. Prod.* MR de `mediagenda/deploiement` ([pooler.yaml](fichiers/M27-E02/mediagenda-deploiement/overlays/prod/pooler.yaml), [paramètres](fichiers/M27-E02/mediagenda-deploiement/overlays/prod/base-pg-stat-statements.yaml), [extrait](fichiers/M27-E02/mediagenda-deploiement/overlays/prod/kustomization.extrait-E02.yaml)) **et** MR de `plateforme/politiques` : l'exception `cnpg-operateur-sans-condense` (M26-E18) ne couvrait que les pods `podRole=instance` ; le Pooler de prod porte le même conteneur d'initialisation à l'image de l'opérateur par **étiquette**, la politique `exiger-digest` refuserait la création de son Deployment ([exception étendue](fichiers/M27-E02/politiques/kyverno/exceptions/cnpg-operateur-sans-condense.yaml) ; ligne du registre des exceptions mise à jour). Sauvegarde `Completed`, MR approuvée, synchronisation manuelle, sonde de `/pret`.

**Explications**

CloudNativePG pousse le principe de Kubernetes jusque dans PostgreSQL : l'état désiré (rôles, base, extensions, réplication, image) est dans un objet, et un réconciliateur rapproche la base de cet objet. Cela rend les rôles **relisibles en MR** et réversibles par Git, mais impose une discipline : l'opérateur ne gère que ce qu'on lui confie (rôles listés), et il **défait** ce qui contredit l'objet (appartenances retirées, `connectionLimit` remise). Les droits sur les tables restent hors de sa portée : c'est le rôle des migrations (objets de l'application) ou d'un SQL de préparation joué une fois (droits de plateforme).

Le pooler ne rend pas la base plus rapide : il **découple** le nombre de clients du nombre de processus PostgreSQL et lisse les reconnexions (bascule, renouvellement des comptes dynamiques). Son prix : une dépendance de plus sur le chemin (d'où deux instances, un PDB et la supervision), et des fonctions de session interdites aux clients en mode transaction.

**Alternatives**
- `DatabaseRole` (CRD, 1.30) plutôt que `managed.roles` : un objet par rôle, qu'une équipe pourrait gérer dans son dépôt sans toucher au Cluster ; en cas de doublon, le Cluster l'emporte (documentation « Coexistence and precedence »). Intéressant pour les accès temporaires.
- PgBouncer en *sidecar* de chaque pod de l'API : pas de saut réseau, mais une réserve par pod (on ne mutualise plus rien) et une configuration par application.
- Pooler `ro` vers les réplicas pour les lectures (rapports) : utile si MédiAgenda séparait ses lectures, ce qu'il ne fait pas.
- Odyssey, PgCat, Supavisor : poolers plus récents (multithread, répartition des lectures) ; non intégrés à CloudNativePG.

**Pièges classiques**
- Changer `spec.cluster` d'un Pooler ou d'une Database : refusé (immuable) ; on crée un autre objet.
- Faire passer le Job de migration par le pooler en mode transaction : verrou consultatif de session libéré au mauvais moment, deux migrations concurrentes possibles.
- Oublier `inRoles` sur un rôle géré qui a des appartenances posées par SQL : révoquées à la réconciliation suivante.
- Laisser `validUntil` à une date passée **et** `ensure: present` : le rôle existe, sans connexion possible — préférer `absent` à l'échéance.
- Croire qu'un `drain` d'un nœud de réplique va « déplacer » l'instance : avec une anti-affinité requise et trois travailleurs, elle attend son nœud.
- Épingler PgBouncer par étiquette seule en prod : refusé par Kyverno (`exiger-digest`).
- Le Pooler de prod « bloqué » sans pod : regarder les événements et les rapports de Kyverno (refus de la création du Deployment), pas le statut du Pooler.

**En production chez MédiSphère**
Alerte sur `cnpg_pgbouncer_pools_cl_waiting` > 0 pendant plus d'une minute et sur `cnpg_pgbouncer_pools_maxwait` (M27-E14) ; revue trimestrielle des rôles gérés et de `pg_stat_statements` (requêtes qui dérivent) ; bascules planifiées annoncées dans un créneau de maintenance, avec `primaryUpdateStrategy: supervised` en prod pour garder la main sur le moment de la bascule lors d'une mise à jour d'image ; PDB et anti-affinité vérifiés par une politique d'admission.

---

### M27-E03 — RabbitMQ par l'opérateur : la grappe `messagerie/rabbitmq`

**Solution**

Fichiers : `plateforme/donnees` : [`outils/recopier-operateurs.sh`](fichiers/M27-E03/donnees/outils/recopier-operateurs.sh), [`vendor/rabbitmq/kustomization.yaml`](fichiers/M27-E03/donnees/vendor/rabbitmq/kustomization.yaml), [`cluster-operator/kustomization.yaml`](fichiers/M27-E03/donnees/vendor/rabbitmq/cluster-operator/kustomization.yaml), [`messaging-topology-operator/kustomization.yaml`](fichiers/M27-E03/donnees/vendor/rabbitmq/messaging-topology-operator/kustomization.yaml), [`rabbitmq/`](fichiers/M27-E03/donnees/rabbitmq/) ([`kustomization.yaml`](fichiers/M27-E03/donnees/rabbitmq/kustomization.yaml), [`certificat.yaml`](fichiers/M27-E03/donnees/rabbitmq/certificat.yaml), [`rabbitmqcluster.yaml`](fichiers/M27-E03/donnees/rabbitmq/rabbitmqcluster.yaml), [`pdb.yaml`](fichiers/M27-E03/donnees/rabbitmq/pdb.yaml), [`reseau.yaml`](fichiers/M27-E03/donnees/rabbitmq/reseau.yaml), [`httproute.yaml`](fichiers/M27-E03/donnees/rabbitmq/httproute.yaml), [`utilisateur-wb-checks.yaml`](fichiers/M27-E03/donnees/rabbitmq/utilisateur-wb-checks.yaml)) ; `plateforme/k8s` : [`espaces/rabbitmq-system.yaml`](fichiers/M27-E03/k8s/espaces/rabbitmq-system.yaml), [`espaces/messagerie.yaml`](fichiers/M27-E03/k8s/espaces/messagerie.yaml) ; `plateforme/gitops` : [`rabbitmq-operateurs.yaml`](fichiers/M27-E03/gitops/plateforme/rabbitmq-operateurs.yaml), [`rabbitmq.yaml`](fichiers/M27-E03/gitops/plateforme/rabbitmq.yaml), [AppProject (extrait)](fichiers/M27-E03/gitops/projets/plateforme.extrait-M27-E03.yaml), [ClusterSecretStore (extrait)](fichiers/M27-E03/gitops/manifestes/external-secrets/clustersecretstore.extrait-M27-E03.yaml) ; `plateforme/secrets` : [`eso-plateforme.hcl` (extrait)](fichiers/M27-E03/secrets/politiques/eso-plateforme.hcl.extrait-M27-E03) ; `plateforme/identite` : [`clients-rabbitmq.tf`](fichiers/M27-E03/identite/tofu/clients-rabbitmq.tf) ; [`docs/donnees/rabbitmq.md`](fichiers/M27-E03/medisphere/docs/donnees/rabbitmq.md).

*A. Les opérateurs.*

1. Le script télécharge **une version donnée**, vérifie l'empreinte écrite dans le script, refuse sinon, et range la copie sous un nom versionné. `--verifier` recontrôle les copies sans rien télécharger (à mettre dans la CI de `plateforme/donnees`). Empreintes relevées : `ae35a547751656bc64bb734026249a845d226d96aba5a73783e05c5ec3444687` (`cluster-operator.yml` 2.23.1), `11a390b02c74397251cdcbee7efac01b1cafc08ac041cd7ab2d69696b6fac0d8` (`messaging-topology-operator-with-certmanager.yaml` 1.20.4).
2. Inventaire (hors CRD) : pour chacun, compte de service, Role/RoleBinding d'élection, ClusterRole(s) et liaisons, Services (webhook, métriques), Deployment, **Certificate + Issuer auto-signé de cert-manager** (certificat du webhook : cert-manager est donc une dépendance des **deux** opérateurs), Mutating/ValidatingWebhookConfiguration. Le `Namespace rabbitmq-system` est déclaré dans les deux fichiers : réunis dans une seule liste `resources`, Kustomize refuse (« may not add resource with an already registered id »).
3. Un `kustomization.yaml` par opérateur retire le `Namespace` (`$patch: delete`) ; celui du dessus réunit les deux et réécrit les images vers `registry.par1.medisphere.internal/ghcr/rabbitmq/…` (étiquette + empreinte). Le Topology Operator reçoit en plus la racine MédiSphère (fichier monté dans `/etc/ssl/certs`, que les programmes Go lisent en entier) : il parle à l'API de gestion **en TLS** quand la grappe a TLS. Les Deployments amont déclarent `runAsNonRoot`, `seccompProfile: RuntimeDefault`, `capabilities.drop: [ALL]`, `allowPrivilegeEscalation: false` : `restricted` sans correctif.
4. Espaces [`rabbitmq-system`](fichiers/M27-E03/k8s/espaces/rabbitmq-system.yaml) et [`messagerie`](fichiers/M27-E03/k8s/espaces/messagerie.yaml) (étiquette `medisphere.internal/exposition: oui` pour la Gateway, **pas** d'étiquette d'équipe : espace de plateforme). L'AppProject `plateforme` accepte le dépôt, les deux espaces et les types de cluster (CRD, ClusterRole(Binding), webhooks). Vérification :
   ```
   admin@adm01:~$ kubectl -n rabbitmq-system get deploy,certificates
   admin@adm01:~$ kubectl get validatingwebhookconfigurations | grep -E 'cluster-operator|messaging-topology'
   ```

*B. La grappe.*

5. Étiquette `4.3.7-management` (dernière corrective au 23/10/2026 ; `4.4.0` publiée le 20/10, évaluée en M27-E15). Points de la 4.3 utiles ici : Khepri par défaut depuis 4.2 pour les **nouvelles** grappes, files miroir absentes depuis 4.0, *feature flags* activés automatiquement à la création d'une grappe neuve.
6. Les fichiers de `rabbitmq/`. Choix importants : image par empreinte ; anti-affinité **requise** par nœud (s'ajoute aux `topologySpreadConstraints` que pose l'opérateur) ; requête = limite mémoire (1 Gio) — l'opérateur en déduit `total_memory_available_override_value` (limite moins 20 %), l'alarme mémoire se lève à 60 % de cette valeur ; `terminationGracePeriodSeconds: 600` au lieu des **7 jours** par défaut (le crochet `preStop` attend que les files quorum gardent leur majorité, puis vide le nœud) ; `disableNonTLSListeners: false` car `true` couperait aussi 15672 (Gateway) et 15692 (Prometheus) — 5672 est fermé par la **politique réseau** ; PDB écrit à la main (l'opérateur n'en crée pas). Le certificat ne porte que des noms sous `svc` (règle du rôle `pki-services/services-k8s`, M25-E16), 72 h au plus.
7. Les trois pods démarrent **ensemble** : l'opérateur pose `podManagementPolicy: Parallel` sur le StatefulSet (source 2.23.1) ; la découverte des pairs par l'API Kubernetes (`rabbit_peer_discovery_k8s`, `target_cluster_size_hint` = 3) fait former **une** grappe à trois nœuds, sans course entre deux formations. Secret `rabbitmq-default-user` : clés `username`, `password`, `default_user.conf`, `host`, `port`, `provider`, `type` (format *service binding*). Lire sans afficher : `kubectl -n messagerie get secret rabbitmq-default-user -o json | jq '.data | keys'`.
8. Diagnostics :
   ```
   admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics cluster_status
   admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics metadata_store_status
   admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_feature_flags name state | grep khepri
   khepri_db	enabled
   admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics alarms
   admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-diagnostics listeners
   ```
   `metadata_store_status` affiche l'état Raft de Khepri (leader, membres) ; `listeners` montre 5671 (`amqp/ssl`), 5672, 15671, 15672, 15691, 15692, 25672. `openssl s_client` (procédure de `rabbitmq.md`) : `subject` du certificat de la PKI de services et `Verify return code: 0 (ok)` avec la racine.

*C. SSO et compte des vérifications.*

9. Client Keycloak **public** avec PKCE (l'interface de gestion est du JavaScript dans le navigateur : la documentation de RabbitMQ le dit, un client confidentiel ne fonctionne pas) ; mappeur d'**audience** `rabbitmq` (RabbitMQ vérifie `aud` = `resource_server_id`) ; rôles du client nommés comme des portées RabbitMQ (`rabbitmq.tag:administrator`, `rabbitmq.configure:*/*`…), lus dans `resource_access.rabbitmq.roles` (`auth_oauth2.additional_scopes_key`) ; `full_scope_allowed = false` pour que le jeton ne porte que les rôles de ce client. Côté RabbitMQ (`additionalConfig`) : `auth_backends.1 = internal`, `auth_backends.2 = oauth2` (utilisateurs internes d'abord), `auth_oauth2.issuer` (découverte des clés de signature, `https.cacertfile` = racine MédiSphère, flux sortant vers 10.10.70.200:443 dans la CNP), `management.oauth_enabled`, `oauth_client_id`, `oauth_scopes = openid profile`. Avec OAuth, l'**interface** ne propose plus que le SSO (`management.oauth_disable_basic_auth`, défaut `true`) ; l'**API HTTP** accepte toujours l'authentification basique (`management.disable_basic_auth`, défaut `false`) — vérifié sur 4.3.7.
10. [`httproute.yaml`](fichiers/M27-E03/donnees/rabbitmq/httproute.yaml) vers le port **15672** (TLS terminé par la Gateway, certificat joker). À la connexion, le nom affiché est le `preferred_username` (`auth_oauth2.preferred_username_claims`), avec l'étiquette `administrator` pour un membre de `plateforme-admins`.
11. `bao kv put -mount=kv plateforme/rabbitmq/wb-checks utilisateur=wb-checks mot_de_passe=@/dev/shm/mdp`, chemin ajouté à `eso-plateforme` (extrait), `messagerie` ajouté aux conditions du ClusterSecretStore (extrait), [`utilisateur-wb-checks.yaml`](fichiers/M27-E03/donnees/rabbitmq/utilisateur-wb-checks.yaml). Fichier local :
    ```
    admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/rabbitmq-checks.env
    admin@adm01:~$ printf 'RABBITMQ_USER=wb-checks\nRABBITMQ_PASSWORD=%s\n' "$(bao kv get -mount=kv -field=mot_de_passe plateforme/rabbitmq/wb-checks)" \
        > ~/.config/workbook/rabbitmq-checks.env
    admin@adm01:~$ lab/bin/check 27 03
    ```
    Sans permission sur un vhost, `wb-checks` ne voit pas ses files (vérifié) : la topologie lui donne une permission **vide** sur chaque vhost (E04).

**Explications**

Deux opérateurs, deux métiers : le **Cluster Operator** fabrique et entretient une grappe (StatefulSet, configuration, Services, découverte des pairs, arrêt propre) ; le **Messaging Topology Operator** parle à l'API HTTP de gestion de cette grappe pour y créer des objets (vhosts, files…) à partir de CRD — il utilise pour cela le compte `rabbitmq-default-user`, d'où son statut de compte critique. Khepri et les files quorum reposent sur Raft : trois nœuds, un par travailleur, et un PDB, c'est la condition pour survivre à un nœud perdu **et** à une maintenance.

**Alternatives**
- Chart Helm communautaire non Bitnami : il n'en existe pas d'officiel ; écrire son propre chart pour deux manifestes amont n'apporte rien.
- Grappe sans opérateur (StatefulSet écrit à la main) : possible, mais il faut réimplémenter l'arrêt propre (`drain`, attente du quorum), la découverte des pairs, la configuration TLS.
- `disableNonTLSListeners: true` + `BackendTLSPolicy` sur la Gateway (Gateway API standard depuis 1.4) : chiffrement de bout en bout jusqu'au pod ; prise en charge par la Gateway Cilium 1.20 à vérifier.
- Secret par défaut dans OpenBao (`spec.secretBackend.vault`) : l'opérateur sait le lire depuis Vault/OpenBao — supprime le Secret Kubernetes de bris de glace ; plus de pièces au démarrage.

**Pièges classiques**
- Le chart Bitnami « parce que c'est plus simple » : images figées depuis août 2025, plus maintenues.
- Une grappe à deux nœuds (ou deux nœuds sur le même travailleur) : la perte d'un nœud fait perdre la majorité.
- Garder les 7 jours de délai d'arrêt : un nœud qui ne peut pas vider ses files bloque le drainage du travailleur pendant une semaine.
- `disableNonTLSListeners: true` sans changer la route : interface et métriques coupées.
- Croire que l'étiquette `monitoring` voit tout : sans permission sur le vhost, l'API répond 404 pour ses files.
- Client Keycloak confidentiel : l'interface n'a pas de secret à présenter ; la connexion échoue.
- Oublier l'audience : jeton valide, refusé par RabbitMQ (`aud`).

**En production chez MédiSphère**
Montées de version répétées dans `wb-essais` (M27-E15) ; supervision des alarmes mémoire et disque, des files sans consommateur et du rebut (M27-E14) ; export nocturne des définitions (M27-E15) ; compte de bris de glace rangé dans OpenBao plutôt que dans un Secret ; redémarrages en roulement par RB-271.

---

### M27-E04 — Topologie déclarative et MédiNotif en recette

**Solution**

Fichiers : `plateforme/donnees` : [`topologie/`](fichiers/M27-E04/donnees/topologie/) ([`kustomization.yaml`](fichiers/M27-E04/donnees/topologie/kustomization.yaml), [`medinotif-recette/`](fichiers/M27-E04/donnees/topologie/medinotif-recette/)), [`rabbitmq/reseau.yaml` (extrait)](fichiers/M27-E04/donnees/rabbitmq/reseau.extrait-E04.yaml) ; `plateforme/gitops` : [`rabbitmq-topologie.yaml`](fichiers/M27-E04/gitops/plateforme/rabbitmq-topologie.yaml), [`projets/medinotif.yaml`](fichiers/M27-E04/gitops/projets/medinotif.yaml), [`applications/medinotif.yaml`](fichiers/M27-E04/gitops/applications/medinotif.yaml), [`secrets/argocd/repo-creds-medinotif.yaml`](fichiers/M27-E04/gitops/secrets/argocd/repo-creds-medinotif.yaml) ; `plateforme/k8s` : [`espaces/medinotif-recette/`](fichiers/M27-E04/k8s/espaces/medinotif-recette/), [`isolement-medinotif-recette.yaml`](fichiers/M27-E04/k8s/composants/reseau/politiques/isolement-medinotif-recette.yaml) ; `plateforme/secrets` : [`eso-espaces.tf` (extrait)](fichiers/M27-E04/secrets/tofu/eso-espaces.tf.extrait), [`eso-plateforme.hcl` (extrait)](fichiers/M27-E04/secrets/politiques/eso-plateforme.hcl.extrait-M27-E04) ; `medinotif/deploiement` : [`base/`](fichiers/M27-E04/medinotif-deploiement/base/), [`overlays/recette/`](fichiers/M27-E04/medinotif-deploiement/overlays/recette/) ; [`docs/donnees/messagerie-topologie.md`](fichiers/M27-E04/medisphere/docs/donnees/messagerie-topologie.md).

*A. Identifiants.*

1. Pour chaque application :
   ```
   admin@adm01:~$ umask 077; openssl rand -base64 30 | tr -d '/+=\n' | head -c 32 > /dev/shm/mdp
   admin@adm01:~$ bao kv put -mount=kv medinotif/recette/amqp utilisateur=medinotif-recette mot_de_passe=@/dev/shm/mdp \
       url="amqps://medinotif-recette:$(cat /dev/shm/mdp)@rabbitmq.messagerie.svc:5671/medinotif-recette"
   admin@adm01:~$ shred -u /dev/shm/mdp
   ```
   (Mot de passe alphanumérique : il finit dans une URL, aucun caractère à encoder. La commande passe le mot de passe en argument de `bao` le temps de l'appel : acceptable sur `adm01` mono-utilisateur, sinon `bao kv put … url=@fichier`.) Exception écrite dans `eso-plateforme.hcl` : deux chemins précis, validés par Sophie.

*B. La topologie.*

2. Chaque objet désigne sa grappe par `rabbitmqClusterReference.name` (et `namespace` s'il est ailleurs) et son vhost par `vhost`. `deletionPolicy: delete` (défaut) supprime l'objet **dans RabbitMQ** quand on supprime la ressource Kubernetes ; `retain` le laisse. Une file est figée à sa création (type, durabilité, arguments) : RabbitMQ refuse une redéclaration différente (`PRECONDITION_FAILED`) et le webhook de l'opérateur refuse la modification de ces champs ; ce qui doit évoluer (rebut, limite de livraison, TTL) va dans une **politique**, modifiable à chaud.
3. Fichiers de `topologie/medinotif-recette/`. Objets Kubernetes préfixés par l'environnement (`medinotif-recette-notifications`), objets RabbitMQ nommés pareil dans chaque vhost (`notifications`). `retain` sur le vhost et les files. Utilisateurs : ExternalSecret (ClusterSecretStore) au format `username`/`password`, `User` sans étiquette. Permission **vide** de `wb-checks` sur le vhost.
4. Vérifications :
   ```
   admin@adm01:~$ set -a; . ~/.config/workbook/rabbitmq-checks.env; set +a
   admin@adm01:~$ curl -s -u "$RABBITMQ_USER:$RABBITMQ_PASSWORD" https://rabbitmq.apps.par1.medisphere.internal/api/queues/medinotif-recette \
       | jq '.[] | {name, type, policy, effective_policy_definition}'
   admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_permissions -p medinotif-recette
   ```
   Publier avec le compte de MédiNotif : `ACCESS_REFUSED - write access to exchange 'notifications' in vhost 'medinotif-recette' refused for user 'medinotif-recette'` (canal fermé par le courtier — vérifié).

*C. Dépôt de déploiement et Argo CD.*

5. `cosign verify --key hashivault://cosign-medisphere registry.par1.medisphere.internal/medisphere/medinotif-worker:<VERSION-MEDINOTIF>` (clé du M25) ou l'indicateur de signature de Harbor. Relever l'empreinte (`crane digest`).
6. Espace : [`00-namespace.yaml`](fichiers/M27-E04/k8s/espaces/medinotif-recette/00-namespace.yaml) avec `medisphere.internal/equipe: mediagenda` (MédiNotif appartient à l'équipe de Julien) — ce qui déclenche **la génération** de `refus-par-defaut` et `sortie-dns` par Kyverno (GeneratingPolicy `networkpolicy-par-defaut`, M26-E16), les règles `exiger-limites` et `interdire-identifiants-url`, et la collecte de Prometheus. Pas d'exposition (worker). `80-openbao.yaml` et rôle `eso-medinotif-recette` (extrait de `eso-espaces.tf`).
7. Base et overlay : Deployment sans privilège (UID 10002 du M12, racine en lecture seule, `/tmp` en `emptyDir`), compte sans jeton, vivacité sur `/metrics`, **pas** de sonde de disponibilité (aucun trafic entrant), `SSL_CERT_FILE` vers la racine montée (pika vérifie le certificat **et** le nom avec le magasin par défaut de Python, que cette variable remplace — vérifié : sans elle, `CERTIFICATE_VERIFY_FAILED`), `MEDINOTIF_DECLARER_FILE=0`, URL depuis le Secret `medinotif-amqp` (ExternalSecret de l'overlay), Service sans adresse + ServiceMonitor, NetworkPolicy de sortie vers les pods `rabbitmq` en 5671. Rendu et contrôle :
   ```
   admin@adm01:~/src/medinotif-deploiement$ kubectl kustomize overlays/recette | kubectl apply --dry-run=server -n medinotif-recette -f -
   ```
   Le *dry-run* côté serveur passe par l'admission : Pod Security et Kyverno répondent comme en vrai (le Deployment est évalué, pas encore ses pods).
8. AppProject `medinotif` (même liste noire que `mediagenda`, ressources orphelines posées par la plateforme ignorées : `openbao`, `eso`, `refus-par-defaut`, `sortie-dns`), ApplicationSet `medinotif` (recette seule, automatique), identifiants du groupe `medinotif` (jeton de déploiement créé sur le **groupe**, rangé dans `kv/plateforme/argocd/depot-medinotif`, ExternalSecret `repo-creds-medinotif`). CNP de la grappe : règle AMQPS depuis `medinotif-recette` (et `mediagenda-recette`, pour E08). Cloison `isolement-medinotif-recette`. Port 9100 dans `collecte-prometheus` (fait en E02).
9. Journal du worker : `{"message": "consommation démarrée", "file": "notifications"}` ; dans l'API de gestion, `consumers: 1` sur la file et une connexion du compte `medinotif-recette` (`/api/connections`, champ `ssl: true`).

*D. Le chemin d'un message.*

10. Avec un *port-forward* et l'outil (il vérifie le certificat sous le nom `rabbitmq.messagerie.svc` alors qu'on joint `127.0.0.1`) :
    ```
    admin@adm01:~$ kubectl -n messagerie port-forward svc/rabbitmq 15671:5671 >/dev/null &
    admin@adm01:~$ export AMQP_MOT_DE_PASSE="$(bao kv get -mount=kv -field=mot_de_passe mediagenda/recette/amqp)"
    admin@adm01:~/DevOpsPrivateCloud/modules/27-donnees-messaging/ressources/E04-messages$ \
        uv run --no-project --with 'pika==1.4.4' publier.py --vhost medinotif-recette --utilisateur mediagenda-recette --valides 10 --invalides 2
    {"confirmes": 12, "refuses": 0, "non_routes": 0}
    admin@adm01:~$ unset AMQP_MOT_DE_PASSE; kill %1
    ```
    (La CNP de la grappe n'a pas de règle pour un *port-forward* : le trafic arrive au pod par le kubelet du nœud, identité `host`/`remote-node` selon la configuration de Cilium. S'il est refusé, ajoute temporairement `fromEntities: [host, remote-node]` sur 5671 le temps de l'essai, ou lance l'outil dans un pod de `mediagenda-recette` — à vérifier sur ton lab.)
11. Journaux : dix `notification envoyée (simulation)` (destinataires masqués), deux `message rejeté`. Prometheus : `sum by (resultat) (medinotif_messages_total{namespace="medinotif-recette"})` → `envoye` 10, `invalide` 2. File `notifications.rebut` : 2 messages ; en-têtes lus par ton compte SSO (`POST /api/queues/medinotif-recette/notifications.rebut/get`, `ackmode: ack_requeue_true`) : `x-death: [{reason: rejected, queue: notifications, exchange: notifications, count: 1}]`, `x-first-death-reason: rejected` (vérifié). Le worker n'a fait que `basic_nack(requeue=False)` : c'est la **file** qui sait où vont ses rebuts (politique).
12. [`messagerie-topologie.md`](fichiers/M27-E04/medisphere/docs/donnees/messagerie-topologie.md).

**Explications**

La topologie est une **API** : décrite dans Git, appliquée par un opérateur, elle devient relisible et reproductible (la prod en E08 est une copie relue). La séparation des comptes donne le principe de moindre privilège au niveau du courtier : MédiAgenda ne peut que publier sur un échange, MédiNotif ne peut que lire une file, ni l'un ni l'autre ne peut créer ou détruire. Le rebut n'est pas une poubelle : c'est une file **durable** qu'une personne relit, rejoue (après correction) ou purge par ticket.

**Alternatives**
- Définitions JSON importées au démarrage (`load_definitions`) : simple, mais statique (redémarrage pour changer) et hors de la réconciliation.
- Déclaration par l'application (ce que faisait MédiNotif avec `MEDINOTIF_DECLARER_FILE=1`) : chaque application peut alors casser la topologie des autres (arguments différents → `PRECONDITION_FAILED`), et doit avoir le droit `configure`.
- OpenTofu (fournisseur `rabbitmq`) : bonne option hors Kubernetes ; ici l'opérateur est déjà là et suit les Secrets.
- Un vhost par **application** plutôt que par environnement : cloisonnement plus fin, mais la publication de MédiAgenda traverse alors deux vhosts (fédération, *shovel*).

**Pièges classiques**
- Déclarer la file avec des arguments (`x-dead-letter-exchange`) au lieu d'une politique : impossible à changer ensuite sans supprimer la file (et ses messages).
- Oublier `MEDINOTIF_DECLARER_FILE=0` : le worker redéclare la file ; refusé (pas de droit `configure`), il boucle sur des reconnexions.
- Oublier `SSL_CERT_FILE` : `CERTIFICATE_VERIFY_FAILED`, boucle de reconnexion — et la tentation de désactiver la vérification.
- Publier un message de test avec de vraies coordonnées.
- `prune: true` sur la topologie avec `deletionPolicy: delete` par défaut : une erreur dans Git supprime une file **et ses messages**.

**En production chez MédiSphère**
Topologie de prod en E08 par copie relue ; alerte sur la profondeur du rebut et sur l'absence de consommateur (M27-E14) ; procédure de rejeu du rebut dans le runbook (M27-E20) ; mise à l'échelle de MédiNotif sur la profondeur de la file par KEDA (M28).

---

### M27-E05 — Flyway : reprendre les migrations de MédiAgenda

**Solution**

Fichiers : `mediagenda/api` : [`Dockerfile.migrations`](fichiers/M27-E05/mediagenda-api/Dockerfile.migrations), [`flyway/rappels/beforeBaseline.sql`](fichiers/M27-E05/mediagenda-api/flyway/rappels/beforeBaseline.sql), [`ci/migrations.yml`](fichiers/M27-E05/mediagenda-api/ci/migrations.yml), [`.gitlab-ci.yml` (extrait)](fichiers/M27-E05/mediagenda-api/.gitlab-ci.yml.extrait-M27-E05) ; `mediagenda/deploiement` : [`components/migrations/`](fichiers/M27-E05/mediagenda-deploiement/components/migrations/) ([`job.yaml`](fichiers/M27-E05/mediagenda-deploiement/components/migrations/job.yaml), [`kustomization.yaml`](fichiers/M27-E05/mediagenda-deploiement/components/migrations/kustomization.yaml)), [`components/identifiants-dynamiques/`](fichiers/M27-E05/mediagenda-deploiement/components/identifiants-dynamiques/), [`livraison` (extrait)](fichiers/M27-E05/mediagenda-deploiement/components/livraison/kustomization.extrait-M27-E05.yaml), [prod (extrait)](fichiers/M27-E05/mediagenda-deploiement/overlays/prod/kustomization.extrait-M27-E05.yaml), [`promouvoir.sh` (extrait)](fichiers/M27-E05/mediagenda-deploiement/outils/promouvoir.sh.extrait-M27-E05) ; essais : [`flyway-essai.yaml`](fichiers/M27-E05/essais/flyway-essai.yaml) ; [`docs/donnees/migrations.md`](fichiers/M27-E05/medisphere/docs/donnees/migrations.md).

*A. Comprendre.*

1. Nomenclature `V<version>__<description>.sql` (deux soulignés ; `V2_1__…` = version 2.1) ; table `flyway_schema_history` (rang, version, description, type `SQL`/`BASELINE`, script, **somme de contrôle**, auteur, date, durée, succès) ; `info` (état, sans rien changer), `validate` (fichiers ↔ historique : sommes de contrôle, versions manquantes), `migrate` (valide puis applique ce qui manque, une transaction par fichier sur PostgreSQL), `baseline` (crée l'historique avec une ligne `BASELINE` à `baselineVersion` : tout ce qui est en dessous est « déjà fait »), `baselineOnMigrate` (fait cette reprise automatiquement si le schéma n'est **pas vide** et n'a **pas** d'historique), `repair` (réaligne les sommes de contrôle et retire les lignes en échec). Rappels SQL : fichiers nommés d'après l'événement (`beforeMigrate.sql`, `beforeBaseline.sql`, `afterMigrate.sql`…) dans un emplacement de migrations. Configuration : `flyway.toml`, arguments `-clé=valeur`, variables `FLYWAY_<CLÉ>` (`baselineOnMigrate` → `FLYWAY_BASELINE_ON_MIGRATE`). Emplacement par défaut dans l'image : `/flyway/sql`. Licence : `/flyway/licenses/LICENSE.md` = **Apache 2.0** ; l'image s'annonce « Flyway OSS Edition 13.11.1 by Redgate ».
2. Sur la recette telle quelle : `migrate` **refuse** (« Found non-empty schema(s) "public" but no schema history table. Use baseline() or set baselineOnMigrate to true ») — vérifié. Avec la reprise sur une base **neuve** : schéma vide → pas de reprise (« a baseline marker will not be added »), V1 et V2 appliquées. Sur une base où V2 manque : la reprise déclarerait V2 faite à tort, l'index unique n'existerait jamais — d'où le garde-fou.

*B. Répétition.*

3-4. [`flyway-essai.yaml`](fichiers/M27-E05/essais/flyway-essai.yaml) : grappe d'une instance, pod de l'**ancien** outil (même image que l'API actuelle), ConfigMap des migrations, pod Flyway non root. Sorties de référence (relevées sur PostgreSQL 18.6, Flyway 13.11.1) :
   ```
   $ flyway info
   Schema history table "public"."flyway_schema_history" does not exist yet
   | Versioned | 1 | init  | SQL | | Pending |
   | Versioned | 2 | index | SQL | | Pending |
   $ flyway migrate
   ERROR: Found non-empty schema(s) "public" but no schema history table. Use baseline() or set baselineOnMigrate to true to initialize the schema history table.
   $ flyway -baselineOnMigrate=true -baselineVersion=2 migrate
   Executing SQL callback: beforeBaseline -
   Successfully baselined schema with version: 2
   Schema "public" is up to date. No migration necessary.
   $ flyway info
   | Versioned | 1 | init                          | SQL      |                     | Below Baseline     |
   | Versioned | 2 | index                         | SQL      |                     | Ignored (Baseline) |
   |           | 2 | reprise de mediagenda.migrate | BASELINE | 2026-10-23 07:14:51 | Baseline           |
   $ flyway validate            # après modification d'un octet de V2 : « Successfully validated », code 0 (vérifié)
   ```
   Note : un fichier **sous** la ligne de reprise n'est pas contrôlé par `validate` (il n'a pas de somme de contrôle dans l'historique) ; modifie `V3` après E06 pour voir « Migration checksum mismatch for migration version 3 ».
5. [`beforeBaseline.sql`](fichiers/M27-E05/mediagenda-api/flyway/rappels/beforeBaseline.sql) : sur une base où seule V1 a été notée, la migration échoue (« garde (M27-E05) : V1 et V2 absentes… »), code 1, **aucune** table d'historique créée (transaction annulée) — vérifié. Puis `kubectl -n wb-essais delete cluster flyway-essai`, `delete pod,configmap …`.

*C. Image et CI.*

6. [`Dockerfile.migrations`](fichiers/M27-E05/mediagenda-api/Dockerfile.migrations) : base par empreinte, migrations dans `/flyway/sql`, rappel à côté (hors du dossier `migrations/` que l'ancien outil refuserait de lire : nom non conforme), `REDGATE_DISABLE_TELEMETRY`, `USER 10004`, commande par défaut `info`. `clean` est refusé par défaut (« Unable to execute clean as it has been disabled with the 'flyway.cleanDisabled' property » — vérifié).
7. Pipeline enfant ([`ci/migrations.yml`](fichiers/M27-E05/mediagenda-api/ci/migrations.yml)) : les composants ont des noms de jobs fixes, les inclure une seconde fois dans le même pipeline écraserait ceux de l'API ; dans un pipeline enfant (`trigger: include`, `strategy: depend`), ils existent une seconde fois, à part, et la signature passe par le runner protégé comme pour l'API. `migrations:verifier` lance Flyway contre un **service** PostgreSQL 18 du job.

*D. Le Job.*

8. [`job.yaml`](fichiers/M27-E05/mediagenda-deploiement/components/migrations/job.yaml) : URL JDBC fixe vers `mediagenda-db-rw` avec `sslmode=verify-full&sslrootcert=` (CA de la grappe, **seule** la clé `ca.crt` du Secret `mediagenda-db-ca` est montée : il contient aussi la clé privée de la CA), utilisateur et mot de passe à part (Secret du propriétaire en dev ; component `identifiants-dynamiques` en recette et prod, dont le modèle fournit désormais `password`), `FLYWAY_CONNECT_RETRIES`, `FLYWAY_LOCK_RETRY_COUNT`, reprise + garde-fou, ressources (JVM), `restricted`. Le component `livraison` vise le nouveau nom de Job et de conteneur ; `promouvoir.sh` promeut **deux** empreintes ; en prod, les deux images par condensé (Kyverno).
9. Après synchronisation de la recette :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette logs job/mediagenda-migrations | grep -E 'baseline|Successfully|Current version'
   Executing SQL callback: beforeBaseline -
   Creating Schema History table "public"."flyway_schema_history" with baseline ...
   Successfully baselined schema with version: 2
   admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -c \
       "SELECT version, type, installed_by FROM flyway_schema_history"
    version |   type   | installed_by
    2       | BASELINE | mediagenda
   ```
   `installed_by = mediagenda` : le migrateur dynamique a pris le rôle `mediagenda` à la connexion (`ALTER ROLE … SET role`, M25-E14) ; la table lui appartient, `DROP ROLE` du compte dynamique à la fin de son bail ne bute sur rien. Supprime l'ancien Job (`kubectl -n mediagenda-recette delete job mediagenda-migrate` : c'était un hook, Argo CD ne le supprime pas de lui-même quand il disparaît du rendu ; c'est le seul geste manuel toléré, sur un objet que Git ne décrit plus). Prod : idem après sauvegarde, MR approuvée, synchronisation manuelle.
10. MR qui retire les trois variables de reprise. Laissées, elles referaient une reprise silencieuse si `flyway_schema_history` disparaissait (restauration partielle, erreur humaine) : Flyway sauterait V1 à V2 **sans vérifier** — et le garde-fou, lui, passerait (l'ancienne table existe toujours). Documentation : [`migrations.md`](fichiers/M27-E05/medisphere/docs/donnees/migrations.md).

**Explications**

Une reprise (*baseline*) ne touche à aucune donnée : elle crée une table d'historique et y écrit une ligne qui dit « tout ce qui est en dessous de 2 est fait ». C'est un engagement : si c'est faux, Flyway ne le saura jamais. D'où le garde-fou, qui s'appuie sur la seule preuve disponible (l'historique de l'ancien outil), et la répétition sur une copie. Le Job garde sa place dans la synchronisation : s'il échoue, l'ancienne version de l'API continue de servir sur l'ancien schéma — c'est ce qui rend la règle « N−1 compatible » (E06) indispensable.

**Alternatives**
- `flyway baseline` lancé **à la main** une fois par environnement (pod jetable avec les identifiants du migrateur) puis Job sans reprise : plus explicite, mais un geste manuel dans un espace applicatif (M20) et la prod n'a pas d'identifiants humains du migrateur (M25 : identifiants de recette seulement).
- Garder l'outil maison : il fait l'essentiel (versions, empreintes, verrou) ; mais ni `validate` séparé, ni reprise, ni rappels, ni retour d'expérience d'une communauté.
- Liquibase 5 (licence FSL depuis 5.0, pilotes JDBC à installer) ; Atlas (édition Community seule sous Apache 2.0, `migrate lint` payant) : comparés dans l'ADR-0270 (M27-E17).
- Migrations dans un conteneur d'initialisation de l'API (M17) : chaque pod migre, la migration tourne pendant le canary… on l'a quitté au M20 pour de bonnes raisons.

**Pièges classiques**
- `FLYWAY_BASELINE_ON_MIGRATE` mal orthographié (`FLYWAY_BASELINEONMIGRATE`) : ignoré sans message, la migration échoue sur « non-empty schema ».
- Le rappel `beforeBaseline.sql` dans `migrations/` : l'ancien outil (encore utilisé par les tests d'intégration) refuse le nom.
- Monter tout le Secret `mediagenda-db-ca` : la clé privée de la CA de la base se retrouve dans le pod de migration.
- L'URL `postgresql://…` du M25 passée à Flyway : il veut du JDBC (`jdbc:postgresql://…`), sans identifiants dans l'URL de préférence.
- Passer par le pooler : verrou consultatif de session perdu entre deux instructions.
- Oublier l'image de migration dans les `images:` de la prod : refusée par Kyverno (`exiger-digest`), synchronisation bloquée à la vague −1.

**En production chez MédiSphère**
Le Job écrit son `info` final dans le journal (Loki) ; une alerte sur un Job `mediagenda-migrations` en échec (`kube_job_status_failed`) ; la MR qui ajoute une migration est relue par Julien **et** par la plateforme (verrous, durée sur la volumétrie de prod, compatibilité N−1 : E06).
