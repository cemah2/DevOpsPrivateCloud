# Versions du bloc G et changements de comportement

> Relevé fait le 23 octobre 2026 au démarrage du bloc G (modules 27 à 29), à partir des sources officielles : index Helm et API d'Artifact Hub, proxy Go (étiquettes des dépôts), PyPI, npm, Maven Central, Docker Hub, pages de publication et notes de version des projets. Les points marqués *non vérifié* sont à confirmer sur le lab ; les exercices concernés le disent. Versions retenues : [`PLAN.md`](../PLAN.md) §6 ; décisions : §4.13.

## Données et messagerie (module 27)

| Outil | Ce qui change pour toi |
|---|---|
| CloudNativePG 1.30.1 (chart 0.29.1) | Déjà installé au M16. 1.30.1 publiée le 23/09/2026 (Kubernetes 1.34 à 1.36). PostgreSQL 18 par défaut. **`spec.backup.barmanObjectStore` est déprécié et sa suppression est annoncée pour la 1.31** : tout l'archivage passe par le plugin Barman Cloud (CRD `ObjectStore`, bloc `plugins`). Le champ `spec.cluster` d'un `Pooler`, d'une `Database` ou d'un `ScheduledBackup` est **immuable** : pour repointer un pooler, on le recrée. Les mots de passe des rôles gérés sont stockés en SCRAM ; les noms de paramètres PostgreSQL sont validés par le webhook. |
| Plugin Barman Cloud 0.15.1 (chart 0.8.1) | Inchangé depuis le M16. Un cluster réplica (`replica.enabled`, `externalClusters` avec le plugin) se nourrit des WAL archivés dans le même `ObjectStore`. |
| PostgreSQL 18.6 | Étiquettes `18.6` disponibles (images `ghcr.io/cloudnative-pg/postgresql:18.6-minimal-trixie` par le cache Harbor). Date exacte de la corrective *non vérifiée*. |
| PgBouncer (Pooler CNPG) | PgBouncer 1.26 (octobre 2026) corrige trois CVE ; la version embarquée dans l'image du Pooler de CNPG 1.30.1 est *non vérifiée* : `kubectl exec … -- pgbouncer --version` en exercice. |
| Patroni 4.1.5 | Publiée le 12/08/2026 (PyPI) ; comparaison seulement, sur trois VMs temporaires avec PostgreSQL 18 du dépôt PGDG et etcd. |
| Valkey 9.1.2 | Publiée le 31/08/2026 (8.1.10 sur la branche 8.1, 9.2 en RC). **9.1** : ACL par base de données, **Lua devient un module** (vérifier qu'il est chargé avant d'utiliser `EVAL`), horloge matérielle activée par défaut. La montée 8.1 → 9.1 se fait sans conversion de données (RDB lu par la 9.1) ; le retour arrière vers 8.1 n'est pas garanti : on le traite comme un aller simple. |
| Chart `valkey-io/valkey-helm` 0.12.0 / `valkey-operator` 0.3.0 | Chart officiel récent (app 9.1.2) ; opérateur jeune (CRD `ValkeyCluster`, mode cluster, pas de Sentinel documenté) : cités, non utilisés. **Bitnami** : depuis le 28/08/2025, `docker.io/bitnami` est figé en `bitnamilegacy` et les charts ne sont plus maintenus : aucune image ni chart Bitnami dans le workbook. |
| Clients Python `redis` 8.1 / `valkey` 6.2 | MédiAgenda garde `redis` 8.1 (protocole compatible) ; pas de prise en charge de Sentinel par une URL : MédiAgenda ne sait parler qu'à un seul point d'accès. |
| Flyway 13.11.1 | 13.0 le 20/07/2026, 13.11.1 le 21/10/2026. Flyway **12.0** (01/2026) a retiré l'espace de configuration `plugin` (`flyway.plugin.*` refusé) ; les images Docker tournent sur **JRE 25** depuis 13.6. Édition Community utilisée (licence à revérifier sur le dépôt `flyway/flyway` : *non vérifié*). `baseline`, `validate`, `info`, `migrate`, `repair` sont dans l'édition Community ; les annulations (`undo`) n'y sont pas. |
| Liquibase 5.0.4 | **Licence FSL-1.1-ALv2 depuis la 5.0** (n'est plus une licence libre au sens de l'OSI) ; Java 17 minimum ; **pilotes JDBC et extensions ne sont plus fournis** (`liquibase lpm add postgresql`) : un `liquibase update` « sorti de la boîte » échoue. Comparaison écrite seulement. |
| Atlas 1.3 | Seule l'**édition Community** (`arigaio/atlas:latest-community`, option `--community` de l'installateur) est sous Apache 2.0 ; le binaire standard est sous licence propriétaire et `migrate lint`, `schema plan` et l'opérateur Kubernetes exigent un compte Pro. Comparaison écrite seulement. |
| RabbitMQ 4.3.x / 4.4.0 | 4.4.0 publiée le 20/10/2026 ; prise en charge communautaire : 4.4 jusqu'en 07/2027, 4.3 jusqu'en 01/2027. **Khepri** est le magasin de métadonnées par défaut depuis 4.2 (Mnesia ne sert plus aux nouvelles grappes). Les **files miroir classiques** n'existent plus depuis 4.0 : files **quorum** (ou *streams*). Le format v2 des files classiques de la 4.4 **empêche le retour en 4.3** : une montée est un aller simple, à répéter dans `wb-essais`. Images officielles `rabbitmq` (Docker Hub). Corrective exacte de la 4.3 à relever au moment de l'installation (≥ 4.3.5 au relevé). |
| Cluster Operator 2.23.1 / Messaging Topology Operator 1.20.4 | Publiés le 13/10/2026. **Pas de chart Helm officiel** : manifestes `cluster-operator.yml` et `messaging-topology-operator-with-certmanager.yaml` des pages de publication, recopiés et épinglés. Compatibilité déclarée avec Kubernetes 1.36 et avec RabbitMQ 4.4 *non vérifiée* (contrôle en exercice). |
| Strimzi 1.3.0 (chart 1.3.0) | Publié le 12/10/2026, testé sur Kubernetes 1.32 à 1.37. **Seule l'API `kafka.strimzi.io/v1` est servie** (v1beta2 retirée en 1.0) : un exemple trouvé en ligne en `v1beta2` est refusé. Kafka **4.2.0 à 4.3.1** seulement. KRaft seul, `KafkaNodePool`. `securityContext` conforme à `restricted` par défaut depuis 1.2 ; Kaniko retiré des constructions de connecteurs. |
| Apache Kafka 4.4.0 / 4.3.1 | 4.4.0 publiée le 20/10/2026 mais **non gérée par Strimzi 1.3** : fixe `spec.kafka.version: 4.3.1`. ZooKeeper supprimé depuis Kafka 4.0. |
| NATS 2.15.1 (chart 2.15.1) | Fiche seulement ; la version du chart suit désormais celle du serveur. |

## Plateforme développeurs (module 28)

| Outil | Ce qui change pour toi |
|---|---|
| KEDA 2.21.0 (chart 2.21.0) | Publiée le 23/09/2026, Kubernetes 1.34 à 1.36. KEDA enregistre l'API `external.metrics.k8s.io` : **un seul** fournisseur de métriques externes par cluster. |
| KEDA HTTP add-on 0.16.0 | **Bêta** : changements cassants possibles avant 1.0. Cité, non installé. |
| Vertical Pod Autoscaler 1.7.1 | 1.8.1 étiquetée le 21/10/2026, mais la documentation d'installation donne encore 1.7.1 : **1.7.1 retenue** (Kubernetes 1.35-1.37). Pas de chart officiel : chart `fairwinds-stable/vpa` 5.1.0 (app 1.7.1). Mode **`InPlaceOrRecreate`** GA depuis VPA 1.6 : la *feature gate* a été retirée en 1.7 (la passer fait échouer le démarrage) ; nouveau mode `InPlace` en alpha. Redimensionnement en place des pods **GA en Kubernetes 1.35**. Les charges qui déclarent des ressources au niveau du pod ne sont pas gérées par le VPA. |
| Backstage 1.56.2 / `@backstage/create-app` 0.9.3 | Publiés les 20-22/10/2026 ; Node.js 22 ou 24 (24 retenu ; version exacte exigée par 1.56 *non vérifiée*). Le **nouveau système de backend** est le seul documenté. Jest est une dépendance de pair depuis 1.46 (à déclarer à la racine). Chart `backstage` 2.10.2 (OCI `ghcr.io/backstage/charts`) : il déploie **ton** image, construite depuis l'application créée. |
| Capsule 0.15.1 (chart 0.15.1) | Publiée le 22/10/2026 ; **exige Kubernetes ≥ 1.36.0** (seule la dernière mineure est prise en charge) : ne l'installe jamais dans un vCluster ni un kind plus ancien. 0.15.0 corrige un **contournement d'autorisation** (GHSA-p8j8-x28r-3c9v) : ne descends pas sous cette version. API `Tenant` *v1beta2* (détails à relire dans la doc de la 0.15). |
| vCluster 0.37.4 (chart `loft/vcluster` 0.37.4) | OSS sous Apache 2.0 (image `vcluster-oss`). L'**etcd embarqué** et les *private nodes* sont réservés à l'édition gratuite enregistrée (« Free », image `vcluster-pro` + plateforme) : reste sur le stockage par défaut. 0.38 en alpha : ne pas l'utiliser. Compatibilité avec Kubernetes 1.36 *non vérifiée*. |
| Crossplane 2.4.3 | Crossplane **v2** : XR à espace de noms par défaut (`apiextensions.crossplane.io/v2`), plus de *claims* pour les nouveaux XR, *patch-and-transform* natif retiré (fonctions de composition seulement), `ControllerConfig` retiré. Fiche seulement. |
| Tilt 0.37.8 / Skaffold 2.25.0 | Fiche seulement. |

## Tests et résilience (module 29)

| Outil | Ce qui change pour toi |
|---|---|
| k6 1.8.2 / xk6 1.4.15 | Versions du 12 et du 22/10/2026 ; k6 suit le versionnement sémantique depuis 1.0. La sortie d'écriture distante Prometheus s'appelle toujours `experimental-prometheus-rw` en 1.8 (vérifié dans le code ; `k6 run --help` ne liste pas les noms des sorties). |
| k6-operator 1.7.0 (chart `grafana/k6-operator` 4.7.0) | Versionnement sémantique depuis 1.0 (09/2025), une mineure toutes les huit semaines. CRD `TestRun` et `PrivateLoadZone`. |
| Chaos Mesh 2.8.6 (chart 2.8.6) | Chart du 21/10/2026. Réglages du runtime containerd (`chaosDaemon.runtime`, `chaosDaemon.socketPath`) à vérifier dans les valeurs de la 2.8 ; compatibilité Kubernetes 1.36 *non vérifiée* (contrôle en exercice). |
| LitmusChaos 3.33 (images) / chart 3.30 | Le chart est en retard sur les images ; ChaosCenter exige MongoDB (sous-chart Bitnami) : **fiche seulement**. |
| Terratest 1.0.1 | Passée en 1.0 (06/2026) ; changements d'API Go par rapport aux 0.x *non vérifiés* : lire le `go doc` du module installé. |
| OPA 1.21.3 / conftest 0.71.1 | **Rego v1 par défaut depuis OPA 1.0** : `if` et `contains` obligatoires, `import rego.v1` inutile ; un exemple en Rego v0 trouvé en ligne échoue (`--v0-compatible` pour l'ancien code, `opa fmt --v0-v1` pour migrer). |
| pytest-testinfra 10.2.2 / Goss 0.4.10 / kubeconform 0.8.0 | Rien de cassant relevé. kubeconform ne connaît pas les CRD : il faut lui fournir leurs schémas (sinon `-ignore-missing-schemas` masque tout). |

## Rappels transverses

- **Bitnami** : aucune image `bitnami/*` ni chart Bitnami (catalogue gratuit figé depuis août 2025) ; Valkey, RabbitMQ, Kafka et MongoDB viennent de leurs projets.
- Les composants ajoutés au bloc G sont installés par **Argo CD** (charts recopiés et signés dans Harbor par `plateforme/charts-miroir`, manifestes amont recopiés quand il n'y a pas de chart), jamais tirés d'Internet par le cluster.
