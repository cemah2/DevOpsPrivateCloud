# Versions des blocs D et E et changements de comportement

> Relevé fait le 22 octobre 2026 au démarrage des blocs D et E (modules 19 à 23), à partir des sources officielles (index Helm des projets, proxy Go qui reflète les étiquettes des dépôts, API de GitLab, PyPI, centre de mise à jour de Jenkins, notes de version et guides de montée de version, avis de sécurité). Les versions de référence sont dans [`PLAN.md`](../PLAN.md) §6. Ce fichier liste ce qui a changé récemment et qui touche les exercices : si un tutoriel plus ancien ne fonctionne plus, la raison est probablement ici. Les lignes marquées *(relecture)* ont été établies pendant la rédaction et la relecture, et sont détaillées dans le corrigé cité.

## Intégration continue (module 19)

| Outil | Ce qui change pour toi |
|---|---|
| GitLab CE 19.4 → 19.5 | La 19.5.0 est sortie le 15/10/2026 (troisième jeudi du mois) ; la 19.4 n'est plus qu'en maintenance (dernière corrective 19.4.3). Le lab part de 19.4.x et monte en 19.5 au palier 3 du M19, runners et agent compris. En 19.5, les variables `CI_JOB_TAGS` et `CI_RUNNER_TAGS` encodent chaque étiquette en JSON : un script qui les découpe à la main doit être revu. |
| GitLab — fonctions par édition | **Free (CE)** : composants CI/CD, catalogue CI/CD de l'instance, `spec:inputs`, agent pour Kubernetes en *CI/CD workflow*. **Premium** : environnements protégés, approbations de déploiement (qui exigent des environnements protégés), usurpation d'identité (*impersonation*) de l'agent. Le workbook protège donc les déploiements par branches protégées, jobs manuels, variables protégées et `resource_group` (ADR-0051, reconduite). |
| GitLab Runner 19.4 / 19.5 (chart 0.93 / 0.94) | Enregistrement par **jeton d'authentification `glrt-`** créé dans l'interface ou par l'API (`POST /user/runners`) ; l'ancien jeton d'enregistrement est « non recommandé » et peut être désactivé par l'administrateur (`410 Gone`). Exécuteur Kubernetes en 19.5 : message explicite quand le conteneur *helper* est tué par manque de mémoire, correction de la classe QoS `BestEffort` sur Kubernetes ≥ 1.34. Garde la même mineure que GitLab. |
| Agent GitLab pour Kubernetes 19.5 | Connexion à KAS par défaut en **`grpcs://`** (au lieu de `wss://`) ; l'ancien mode fonctionne encore, la migration passe par `config.kasAddress` du chart. |
| BuildKit 0.34 / Kaniko | BuildKit 0.34.1 (07/10/2026), mode *rootless* en démon partagé. **Kaniko est archivé** par Google depuis juin 2025 (dernière version 1.24.0) ; le fork de Chainguard (1.25.x) n'assure que la maintenance : cité, jamais utilisé. |
| Buildah | 1.46 amont (module Go déplacé vers `go.podman.io/buildah`) ; le workbook garde la 1.39 de Debian 13. |
| Jenkins LTS 2.580 | **Java 21 ou 25 obligatoire** depuis la 2.555.1 (contrôleur et agents ; images Java 17 retirées). Configuration as Code : la section `crumbIssuer` doit être retirée, sinon Jenkins refuse de démarrer. Chart `jenkinsci/jenkins` 5.9.x. |
| SonarQube Community Build 26.10 | Groupe « Anyone » supprimé : **plus d'analyse anonyme**, un jeton est toujours nécessaire. Le chart `sonarqube/sonarqube` 2026.5 change de numérotation, gère lui-même les sondes (anciennes valeurs ignorées), retire le sous-chart ingress-nginx (`httproute` disponible), demande 4 Gi et limite à 10 Gi par défaut, et déploie encore la 26.9 : forcer l'image 26.10. PostgreSQL 15 à 18. Édition communautaire : analyse de la seule branche principale, sans décoration des MR. |
| Semgrep CE 1.18x / Opengrep | Les règles du registre Semgrep sont sous « Semgrep Rules License v1.0 » depuis décembre 2024 (usage interne autorisé, pas de produit concurrent). Opengrep (fork LGPL) est cité comme alternative. |
| Trivy 0.76 | 0.76.1 publiée le 21/10/2026 ; le workbook reste sur 0.75 épinglée par empreinte (M13) tant que les notes de la 0.76 ne sont pas relues. Rappel : jamais 0.69.4 à 0.69.6 (CVE-2026-33634). |

## GitOps (module 20)

| Outil | Ce qui change pour toi |
|---|---|
| Argo CD 3.5 (chart 10.10) | Kubernetes **1.33 à 1.36** testés. Rappels de la 3.0 : suivi des ressources par **annotation** par défaut (plus par l'étiquette `app.kubernetes.io/instance`), droits RBAC distincts pour les journaux, exclusions de ressources par défaut étendues. 3.5 : Helm 4 embarqué (`helm.version` ignoré, OCI plus strict), `known_hosts` par `argocd-ssh-known-hosts-cm`, GnuPG remplacé par *Source Integrity*, *Source Hydrator* en bêta, `--repo-server-strict-tls` déprécié. La 3.6 (GA prévue le 03/11/2026) n'est pas retenue. |
| Argo Rollouts 1.10 (chart 2.43) | Pas de routeur de trafic Cilium natif : le canary passe par le plugin **Gateway API 0.17.0** (`rollouts-plugin-trafficrouter-gatewayapi`) qui ajuste les poids des HTTPRoute de la Gateway Cilium ; l'étiquette v1.0.0 du plugin date de 2024 et n'est pas la dernière. Rupture possible pour Traefik v2 (sans objet ici). |
| Flux 2.9 | Kubernetes 1.34 à 1.36. API `image…/v1beta2` et `notification…/v1beta2` supprimées : `flux migrate` avant toute montée. Post-rendu Helm : `combined` par défaut au lieu de `nohooks`. Flux Operator (`FluxInstance`) 0.61 en alternative à `flux bootstrap`. |
| Kargo 1.12 | Cité dans la fiche de promotion entre environnements. |

## Métriques et alertes (module 21)

| Outil | Ce qui change pour toi |
|---|---|
| Prometheus 3.15 (LTS 3.13) | Rappels de la 3.0 : noms UTF-8, `scrape_protocols`, nouvelle interface, *remote write* 2.0, réception OTLP native, `holt_winters` renommé `double_exponential_smoothing` (expérimental). 3.9 : histogrammes natifs stables, l'option de fonctionnalité disparaît au profit de `scrape_native_histograms`. 3.14 : expressions de durée actives par défaut. 3.15 : `--log.level` déprécié au profit de `runtime.log_level`. La LTS 3.5 est en fin de vie depuis le 31/07/2026. |
| kube-prometheus-stack 92 | Images **distroless** par défaut depuis la 85. Depuis la 90, les ServiceMonitors du plan de contrôle n'utilisent plus `bearerTokenFile`/`caFile` mais `authorization`/`tlsConfig`, et un Secret de jeton longue durée est créé. Depuis la 92, `nodeSelector: kubernetes.io/os: linux` partout. Le sous-chart Grafana vient de `oci://ghcr.io/grafana-community/helm-charts`. Lis `UPGRADE.md` du chart avant chaque majeure. |
| prometheus-operator 0.94 | `ScrapeConfig` et `AlertmanagerConfig` restent en **`v1alpha1`**, avec des validations de plus en plus strictes. 0.93 : `shards: 1` par défaut. 0.94 : RBAC sans verbes génériques. |
| Alertmanager 0.34 | 0.33 : option `--auto-gomaxprocs` et métrique `alertmanager_marked_alerts` supprimées. 0.34 : nouvelles valeurs du label `reason` des échecs de notification. |
| Grafana 13.2 | Le chart **déménage** : `grafana/grafana` est déprécié, utiliser `grafana-community/grafana` (14.x, `values.schema.json` strict). Grafana 13 : schéma de tableau de bord **v2** actif par défaut (migration à l'ouverture), Git Sync en GA, `/api` déprécié au profit de `/apis`, `grafana-cli` et `grafana-server` supprimés, Image Renderer supprimé. Chart distroless à système de fichiers en lecture seule : `GF_INSTALL_PLUGINS` et `GF_*__FILE` ne fonctionnent plus comme avant. |
| Thanos 0.42 / Mimir 3 | Thanos 0.42 retire `--shipper.ignore-unequal-block-size`. **Mimir 3** passe à une ingestion par **Kafka** activée par défaut dans le chart 6.x (une dizaine de composants) : trop lourd pour le lab, d'où Thanos. **Bitnami** a retiré son catalogue d'images gratuites en 2025 : n'utilise ni ses charts ni ses images. |
| kube-state-metrics 2.20 | `kube_pod_status_reason` n'émet plus que la raison active : les requêtes en `== 0` sont à revoir. |
| Pyrra 0.10 / Sloth 0.16 | Pyrra très actif mais **sans chart officiel** (manifestes amont ; le chart communautaire pointe sur une ancienne version). Sloth ralentit (dernière version en avril 2026) : utilisé en CLI pour comparer. |

## Journaux (module 22)

| Outil | Ce qui change pour toi |
|---|---|
| Loki 3.7 (chart `grafana-community/loki` 19) | Le chart **déménage** (`grafana/loki` ne sert plus qu'à l'édition Enterprise). Mode `Monolithic` (ancien `SingleBinary`, renommé en 12.0) ; **SimpleScalable déprécié**, supprimé en Loki 4. Chart 18 : label `cluster` remplacé par `app_instance` ; chart 19 : les Services *headless* n'héritent plus des labels et annotations. Loki 3.8 (non retenue) retire BoltDB, Cassandra, DynamoDB et Promtail : schéma **TSDB v13** obligatoire. |
| Promtail | **Fin de vie le 2 mars 2026** : jamais utilisé, migration vers Alloy (`alloy convert --source-format=promtail`). |
| Grafana Alloy 1.21 | 1.19 : `prometheus.operator.servicemonitors` ignore `bearerTokenFile`. 1.21 : le WAL de `loki.write` exige `--stability.level=experimental` ; `prometheus.write.queue` supprimé ; `Base64Decode` retiré d'OTTL. |
| Fluent Bit 5.1 | 5.0 : `fluentbit_hot_reloaded_times` devient un compteur ; `retain_metadata_in_forward_mode=true` (Fluentd le rejette) ; `storage.pause_on_chunks_overlimit` activé automatiquement. |
| OpenSearch 3.9 | `vm.max_map_count ≥ 262144` sur les nœuds ; une ligne 2.x (2.19) reste maintenue. opensearch-operator 3.0 renomme son groupe d'API en `opensearch.org/v1` (non utilisé). |

## Traces et profilage (module 23)

| Outil | Ce qui change pour toi |
|---|---|
| OpenTelemetry Collector 0.16x | Depuis la 0.144, l'exportateur `otlp` s'appelle **`otlp_grpc`** et `otlphttp` **`otlp_http`** (anciens noms en alias dépréciés). Métriques internes sur `localhost` par défaut ; métriques du `memory_limiter` renommées. |
| SDK Python 1.45 / instrumentations 0.66b | Python 3.9 abandonné ; conventions sémantiques HTTP stables encore sur option (`OTEL_SEMCONV_STABILITY_OPT_IN=http`, à vérifier sur ta version) ; signal des journaux encore en stabilisation, API *Events* supprimée. |
| SDK Go 1.47 / otelhttp 0.72 | Conventions HTTP stables ; vérifie le paquet `semconv/v1.xx` importé par ta version. |
| Tempo 3.1 (chart `grafana-community/tempo` 3.2) | Le chart **déménage**. Tempo 3 supprime *ingester* et *compactor* (remplacés par *live-store* et un ordonnanceur/travailleurs) ; Kafka obligatoire en microservices, **pas en monolithique** ; `vParquet3` refusé en 3.1. Chart 3.2 : `tempo.retention` (24 h par défaut) enfin appliquée : fixe-la explicitement. |
| Jaeger 2.22 | Jaeger v2 est construit sur le Collector OpenTelemetry ; **Jaeger v1 en fin de vie** (31/12/2025), `jaeger-operator` figé. |
| Pyroscope 2.4 | La 2.0 passe au stockage v2 (*segment-writer*, *metastore*) avec **stockage objet requis**. |
| Beyla / OBI | Beyla est une distribution d'OpenTelemetry eBPF Instrumentation (OBI 0.15, sans statut stable) : découverte seulement. |
