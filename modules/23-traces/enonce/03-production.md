# Module 23 — Palier 3 : Production

Les paliers 1 et 2 ont monté la chaîne : l'opérateur OpenTelemetry, les agents `otel-agent` sur chaque nœud, la passerelle `otel-passerelle` à deux réplicas qui échantillonne en queue, Tempo sur le RGW, MédiAgenda et MédiDoc instrumentées dans le code, des traces distribuées, les liens entre métriques, journaux et traces. Il manque ce qui en fait un service de production. Karim Benali veut des **métriques tirées des traces** (graphe de services, tableaux RED) sans réinstrumenter quoi que ce soit, et voir **le profil CPU** de l'API quand elle sature. Claire Morel veut que l'équipe ait comparé Tempo à **Jaeger**, la référence historique, avant d'écrire l'ADR. Sophie Laurent refuse que le point d'entrée OTLP `10.10.41.63` reste ouvert, en clair et sans authentification, et Nadia Roussel veut savoir combien de jours de traces on garde et ce qui arrive quand on dépasse les limites. Le palier se termine par l'ADR-0230 et un questionnaire de production.

Prérequis : paliers 1 et 2 du module (`lab/bin/check 23 02`, `03`, `04`, `06`, `08` et `09` verts) ; M21 (`metriques-v1` : kube-prometheus-stack, Thanos, Grafana, Pyrra), M22 (`journaux-v1` : Loki, Alloy), M20 (Argo CD, `plateforme/charts-miroir`), M15 (cert-manager, ExternalDNS, CiliumNetworkPolicy), M16 (RGW de `ceph-par1` depuis les travailleurs).

> **Rappels du module** (introduction) : toute modification passe par le code et Argo CD. Configurations des Collectors dans `plateforme/observabilite/otel/` (Application `otel`), values de Tempo dans `tempo/` (Application `tempo`), de kube-prometheus-stack dans `kps/`, tableaux dans `tableaux/` ; applications par MR dans leurs dépôts (`mediagenda/api`, `medidoc/medidoc`, `…/deploiement`), promues par GitOps. Les Secrets ne sont jamais dans Git : `plateforme/k8s/outils/secrets-k8s.sh` à partir d'Ansible Vault `critique`. Tout nouveau flux réseau va dans la matrice (`docs/socle/matrice-flux.md` ou `docs/kubernetes/reseau/matrice-flux-cluster.md`). La documentation de ce module vit dans `docs/observabilite/traces/` de `plateforme/medisphere`.

> ⚠️ **Mémoire** : ce palier ajoute Pyroscope (≈ 1 Go) de façon permanente et Jaeger (≈ 1 Go) le temps de M23-E15. Vérifie la marge des travailleurs avant (`kubectl top nodes`, tableau « nœuds » du M21) ; Jaeger ne doit jamais cohabiter avec un autre composant temporaire (PLAN §4.11).

---

### M23-E13 — Métriques tirées des traces : graphes de services et RED  `LAB` `★★★`

> **Ticket PLAT-2413** — *De : Karim Benali*
> Les équipes me demandent « qui appelle qui, et à quelle vitesse » à chaque revue d'architecture. Les traces le savent : Tempo sait en tirer des métriques. Je veux le graphe de services dans Grafana et un tableau RED de MédiAgenda tiré des traces, **à côté** de celui des métriques applicatives, avec une explication écrite de l'écart entre les deux. Et je ne veux pas d'explosion de cardinalité dans Prometheus.

**Objectifs pédagogiques**
- Activer le *metrics-generator* de Tempo 3 (processeurs `service-graphs` et `span-metrics`) et l'écriture distante vers Prometheus, en tenant compte des deux réplicas de Prometheus et de Thanos.
- Lire les séries produites (`traces_service_graph_*`, `traces_spanmetrics_*`) et leurs étiquettes, et borner leur cardinalité.
- Comprendre pourquoi des métriques tirées de traces **échantillonnées** ne sont pas des métriques de trafic.

**Prérequis** : M23-E03 (Tempo), M23-E06 (traces distribuées MédiAgenda → MédiDoc), M23-E09 (échantillonnage), M21-E24 (Prometheus à deux réplicas, Thanos Query sur 10.10.41.60).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Prometheus du cluster : CR `kps-prometheus` (espace `supervision`), pods `prometheus-kps-prometheus-0` et `-1`, Service sans tête `prometheus-operated`. Thanos Query déduplique les deux réplicas par leur étiquette externe de réplica (M21-E24).
- En Tempo 3 **monolithique**, le distributeur passe les spans au *metrics-generator* dans le même processus : pas de Kafka. Les processeurs s'activent par locataire dans `overrides` (ici, les valeurs par défaut, Tempo n'étant pas multi-locataire).
- Le chart `grafana-community/tempo` 3.2 expose `tempo.metricsGenerator` (activation, processeurs, `storage.remote_write`) et `tempo.overrides.defaults`.
- Les traces arrivent après l'échantillonnage en queue de M23-E09 (erreurs et lentes à 100 %, le reste à 10 %).

**Travail demandé**
1. Dans `kps/values.yaml`, active le **récepteur d'écriture distante** de Prometheus et vérifie que le stockage des exemplars est actif (M23-E08). Avant de pousser : qui pourra écrire dans Prometheus une fois le récepteur ouvert ? Ajoute la CiliumNetworkPolicy qui le restreint au seul Tempo (méthode et chemin), et reporte le flux dans la matrice du cluster.
2. Dans `tempo/values.yaml`, active le *metrics-generator* : processeurs `service-graphs` et `span-metrics`, une dimension supplémentaire pour l'environnement (`deployment.environment.name`), des seuils d'histogramme adaptés à une API web, une limite de séries actives, et l'écriture distante **avec les exemplars**, sous le nom d'étiquette que Grafana attend depuis M23-E08 (`trace_id`). Choisis la ou les cibles d'écriture en sachant que Prometheus a deux réplicas : écris dans `docs/observabilite/traces/metriques-depuis-traces.md` pourquoi viser le Service `kps-prometheus` serait une erreur.
3. Fais générer du trafic sur MédiAgenda en recette (l'outil de charge de M21-E23 suffit, quelques requêtes par seconde pendant 15 min) et explore les séries dans Thanos Query : noms, étiquettes (`service`, `span_name`, `span_kind`, `status_code`, `client`, `server`, `connection_type`), nombre de séries (`count({__name__=~"traces_.*"})`). Quels nœuds du graphe ne sont pas des services instrumentés ?
4. Déclare dans la source Grafana `Tempo` (par le code, là où tu l'as déclarée en M23-E03) le lien vers Prometheus pour le **graphe de services** et pour les requêtes RED depuis une span. Ouvre l'onglet *Service Graph* d'Explore.
5. Construis le tableau **« MédiAgenda — RED depuis les traces »** (UID `m23-red-traces`, dans `tableaux/`, source en variable `${datasource}`, variable d'environnement) : débit, erreurs et latence p95, chaque fois tiré des métriques applicatives (`mediagenda_http_*`) **et** des span metrics, plus les appels sortants du graphe de services. Ajoute les règles d'enregistrement RED tirées des traces dans `regles/` (convention `niveau:métrique:opérations` du M21).
6. Explique dans `metriques-depuis-traces.md` les écarts observés entre les deux sources (débit, taux d'erreurs, p95) en les reliant à l'échantillonnage, et dis à quoi servent vraiment ces séries (graphe de services, RED des services **non** instrumentés en métriques, exemplars) et à quoi elles ne doivent pas servir (SLO, facturation, alertes de débit). Donne le nombre de séries mesuré et la limite posée.

**Critères de réussite**
- [ ] Prometheus accepte l'écriture distante et seul Tempo peut y écrire (CNP) ; Tempo écrit sur les **deux** réplicas, exemplars compris.
- [ ] Les séries `traces_spanmetrics_calls_total` existent pour `mediagenda-api` et `medidoc`, et `traces_service_graph_request_total` montre l'arête `mediagenda-api` → `medidoc` et l'arête vers la base de données.
- [ ] La limite de séries actives du *metrics-generator* est posée ; le nombre de séries mesuré est écrit.
- [ ] Le tableau `m23-red-traces` est provisionné depuis `tableaux/` et compare les deux sources ; `metriques-depuis-traces.md` explique l'écart.

**Vérification** : `lab/bin/check 23 13`

<details><summary>Indice 1</summary>

La documentation de Tempo, page *Metrics-generator* et section `metrics_generator` / `overrides` de la configuration, liste les processeurs (`service-graphs`, `span-metrics`…) et la clé `max_active_series`. Une écriture distante Prometheus accepte `send_exemplars`. Vérifie le rendu avant de pousser : `helm template` du chart recopié avec tes values, puis `-config.verify` du binaire `tempo` si tu l'as sous la main.
</details>

<details><summary>Indice 2</summary>

Deux réplicas de Prometheus qui collectent les mêmes cibles ont les mêmes séries ; Thanos Query en garde une. Si Tempo écrit sur un Service équilibré, chaque échantillon n'arrive que sur **un** réplica : chacun a des trous, et la déduplication ne les bouche pas forcément au bon moment. Le Service `prometheus-operated` donne un nom DNS stable à chaque pod (`<pod>.prometheus-operated.supervision.svc`).
</details>

<details><summary>Indice 3</summary>

Pour comparer les débits, rapporte `sum(rate(traces_spanmetrics_calls_total{service="mediagenda-api", span_kind="SPAN_KIND_SERVER"}[5m]))` à `sum(rate(mediagenda_http_requests_total{…}[5m]))` sur les mêmes routes (sans les sondes). Le rapport devrait ressembler à ta politique d'échantillonnage ; le taux d'erreurs tiré des traces, lui, sera **plus haut** que la réalité. Pourquoi ?
</details>

**Pour aller plus loin** : le connecteur `spanmetrics` du Collector calcule les mêmes séries **avant** l'échantillonnage en queue (dans un pipeline dédié de la passerelle) : compare son coût en séries et en mémoire avec le *metrics-generator*. Regarde aussi `span_multiplier_key` et l'échantillonnage probabiliste avec `tracestate` (`enable_tracestate_span_multiplier`) : à quelles conditions des span metrics échantillonnées peuvent-elles être redressées ?

---

### M23-E14 — Profilage continu avec Pyroscope  `LAB` `★★★`

> **Ticket DEV-2414** — *De : Karim Benali, en copie Julien Petit*
> Quand l'API sature, la trace nous dit « 400 ms dans le handler », pas **quelle ligne**. Je veux un profilage continu des deux applications : MédiAgenda par le SDK Python, MédiDoc par `pprof` (pas d'agent dans l'image Go), le tout stocké dans Pyroscope sur le RGW, et si possible un lien direct d'une span à son profil. Montre-moi un *flame graph* de l'API sous charge et dis-moi ce qu'il coûte.

**Objectifs pédagogiques**
- Déployer Pyroscope 2 (stockage objet obligatoire) par Argo CD, avec un compartiment RGW et une identité dédiés.
- Profiler une application Python en mode *push* (SDK `pyroscope-io`) et une application Go en mode *pull* (`net/http/pprof`, `godeltaprof`, `pyroscope.scrape` d'Alloy).
- Lire un *flame graph* (largeur, profondeur, temps propre), comparer deux périodes, et relier une span à son profil.

**Prérequis** : M23-E04, M23-E06 et M23-E08 (applications instrumentées et corrélées : le code de ce ticket part de leur état), M22-E03 (Alloy en DaemonSet), M20-E13 (`charts-miroir`), M16 (RGW depuis les travailleurs).
**Durée indicative** : 3 h.

**Contexte technique**
- Pyroscope 2.4 : chart `grafana/pyroscope` 2.4.x (à recopier par `charts-miroir`), Application **`pyroscope`**, espace `traces`, Service `pyroscope:4040`. Le chart embarque **son propre Alloy**, activé par défaut : le lab garde un seul collecteur, celui du M22.
- Compartiment RGW **`pyroscope-k8s-par1`**, utilisateur RGW `pyroscope` (`radosgw-admin` sur `ceph-par1`, avec quota, comme pour Tempo en M23-E03), Secret `pyroscope-objstore` hors Git, identité de lecture pour les checks dans `~/.config/workbook/s3-pyroscope.env` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, en 600).
- Le client S3 de Pyroscope n'a pas d'option « fichier de CA » ; le certificat du RGW est signé par la racine MédiSphère.
- MédiAgenda : `pyroscope-io` 1.4 (roues pour Python 3.13), lien span → profil par `pyroscope-otel` (`PyroscopeSpanProcessor`). MédiDoc : `net/http/pprof` et `github.com/grafana/pyroscope-go/godeltaprof` sur un **port interne** (6060), jamais sur le port de l'API ni derrière un Service.
- Noms : `service_name` des profils = `OTEL_SERVICE_NAME` des traces (`mediagenda-api`, `medidoc`) ; c'est la clé du lien Tempo → Pyroscope.

**Travail demandé**
1. Crée l'utilisateur et le compartiment RGW, le Secret `pyroscope-objstore` (par `secrets-k8s.sh`, composant `pyroscope`, depuis Vault) et l'identité de lecture des checks. Recopie le chart par `charts-miroir`.
2. Écris `pyroscope/values.yaml` (monolithique, stockage S3 sur le RGW avec la racine MédiSphère, rétention de 14 jours, limites d'ingestion, volume persistant, sous-chart Alloy **désactivé**, ServiceMonitor) et l'Application `pyroscope`. Vérifie le rendu (`helm template`) avant la MR.
3. MédiAgenda (MR dans `mediagenda/api`) : ajoute `pyroscope-io` et `pyroscope-otel`, démarre le profileur **seulement** si une variable d'adresse est fournie, avec le même nom de service que les traces et des étiquettes `version` et `environnement`, et branche le processeur de spans sur le fournisseur de traces de M23-E04. Fournis l'adresse par un composant kustomize de `mediagenda/deploiement` et ouvre la sortie des pods de MédiAgenda vers Pyroscope (leurs espaces sont en refus par défaut), puis promeus en dev puis en recette.
4. MédiDoc (MR dans `medidoc/medidoc`) : expose les profils `pprof` et `godeltaprof` sur un serveur séparé, activé par une variable ; déclare le port de conteneur nommé `pprof` dans `medidoc/deploiement` sans le publier par un Service. Côté plateforme : ajoute à la configuration d'Alloy la découverte des pods MédiDoc, `pyroscope.scrape` (CPU et profils delta) et `pyroscope.write` ; ouvre le flux Alloy → port 6060 par une CiliumNetworkPolicy qui **n'enferme pas** les pods MédiDoc dans un refus par défaut.
5. Ajoute la source Grafana `Pyroscope` par le code et le lien **traces → profils** dans la source `Tempo` (`tracesToProfiles`). Ouvre une trace de MédiAgenda et suis le lien ; note ce qui marche et ce qui ne marche pas.
6. Sous charge (15 min, quelques dizaines de requêtes par seconde sur la recette), lis le *flame graph* de MédiAgenda : où passe le CPU (sérialisation, pilote PostgreSQL, calcul des créneaux, profileur lui-même) ? Compare avec une période calme (vue *diff*). Mesure le **surcoût** du profilage : CPU et mémoire des pods avec et sans profileur, à charge égale. Rédige `docs/observabilite/traces/profilage.md` : lecture d'un flame graph, surcoût mesuré, ce qu'un profil CPU ne montre pas.

**Critères de réussite**
- [ ] Application `pyroscope` Synced/Healthy, pod prêt, objets dans `pyroscope-k8s-par1`, aucun Alloy en plus de celui du M22.
- [ ] Profils CPU récents de `mediagenda-api` et `medidoc`, profils mémoire de `medidoc`, chacun avec le même nom de service que ses traces.
- [ ] Le port `pprof` n'est publié par aucun Service ; seul Alloy le joint.
- [ ] La source `Tempo` mène aux profils ; `profilage.md` contient une lecture de flame graph et le surcoût mesuré.

**Vérification** : `lab/bin/check 23 14`

<details><summary>Indice 1</summary>

Pour la CA : la bibliothèque TLS de Go lit aussi `SSL_CERT_DIR` (liste de répertoires séparés par `:`). Le chart Pyroscope accepte des variables d'environnement, des volumes et une configuration structurée (`structuredConfig`) fusionnée à la sienne ; `-config.expand-env=true` permet `${VAR}` dans cette configuration.
</details>

<details><summary>Indice 2</summary>

Côté Alloy, `discovery.kubernetes` (rôle `pod`, limité aux espaces de MédiDoc et au nœud de l'instance), un `discovery.relabel` qui garde le port nommé `pprof` et pose `service_name`, puis `pyroscope.scrape` avec un bloc `profiling_config` (`profile.process_cpu`, `profile.godeltaprof_memory`… et les profils non delta désactivés). Le DaemonSet Alloy du chart définit `HOSTNAME` avec le nom du nœud.
</details>

<details><summary>Indice 3</summary>

Le lien span → profil de `pyroscope-otel` étiquette les échantillons **du fil qui a démarré la span racine**. Où FastAPI exécute-t-il un gestionnaire déclaré avec `def` (et non `async def`) ? Regarde le nombre d'échantillons attachés à un `span_id` avant de conclure que « le lien ne marche pas ».
</details>

**Pour aller plus loin** : profile la mémoire de MédiAgenda (`mem_enabled`) le temps d'une charge, et compare le surcoût. Regarde ce qu'apportent les profils eBPF (Alloy `pyroscope.ebpf`, OBI) : plus d'instrumentation dans le code, mais quels privilèges sur les nœuds ?

---

### M23-E15 — Jaeger v2 en comparaison  `LAB` `★★`

> **Ticket PLAT-2415** — *De : Claire Morel*
> Avant de signer l'ADR des traces, je veux que l'équipe ait essayé Jaeger, la référence CNCF que tout le monde cite en entretien. Une demi-journée, pas plus : même trafic que Tempo, une comparaison écrite et chiffrée, puis on retire tout. Rien ne doit rester de l'essai.

**Objectifs pédagogiques**
- Déployer Jaeger 2 (construit sur le Collector OpenTelemetry) le temps d'un essai, et lui envoyer les mêmes traces qu'à Tempo sans coupler les deux destinations.
- Comparer deux magasins de traces sur des critères mesurables : stockage, langage de requête, liens avec les autres signaux, ressources, exploitation.
- Retirer proprement un composant temporaire géré par Argo CD.

**Prérequis** : M23-E09 (passerelle), M23-E13 (graphe de services).
**Durée indicative** : 2 h.

**Contexte technique**
- Jaeger **2.22** : chart `jaegertracing/jaeger` 4.16.x (à recopier par `charts-miroir`), un binaire *all-in-one* dont la configuration est celle d'un Collector (extensions `jaeger_storage`, `jaeger_query`, exportateur `jaeger_storage_exporter`). Jaeger v1 est en fin de vie depuis le 31/12/2025.
- Espace **`jaeger-essai`**, stockage **en mémoire** (pas de base pour un essai), interface sur le port 16686 du Service `jaeger`, par `kubectl port-forward` (aucune exposition).
- Les exportateurs du Collector ont chacun leur file d'attente : un exportateur en échec ne bloque pas les autres.

**Travail demandé**
1. Recopie le chart, écris `jaeger-essai/values.yaml` (image par le cache Harbor, ressources bornées, configuration explicite : récepteur OTLP sur toutes les interfaces du pod, mémoire limitée à un nombre de traces) et l'Application `jaeger-essai` (création de l'espace par Argo CD).
2. Ajoute à la passerelle un second exportateur vers Jaeger dans le pipeline de traces, avec sa propre file d'attente et des reprises courtes. Vérifie dans les métriques de la passerelle que Tempo ne perd rien quand tu arrêtes Jaeger (`kubectl scale … --replicas=0` le temps d'une minute).
3. Compare, à trafic égal pendant au moins 30 min : retrouver une trace par son identifiant, par attribut (`http.route`, statut, durée), par structure (une span lente **sous** un appel à MédiDoc) ; graphe de dépendances ; lien vers les journaux et les métriques depuis Grafana ; mémoire et CPU des deux (`kubectl top`, Prometheus) ; ce qu'il faudrait pour garder 14 jours de traces dans chacun.
4. Rédige `docs/observabilite/traces/comparatif-jaeger.md` (tableau critère par critère avec tes mesures, puis une recommandation et sa décision) : il nourrit l'ADR de M23-E17.
5. Retire l'essai : exportateur et pipeline de la passerelle, Application (sans laisser d'objets orphelins), espace `jaeger-essai`. Vérifie qu'aucune métrique d'erreur d'export ne reste.

**Critères de réussite**
- [ ] `comparatif-jaeger.md` contient des mesures chiffrées (mémoire, CPU) et une décision argumentée.
- [ ] L'espace `jaeger-essai` et l'Application ont disparu ; la passerelle n'a plus d'exportateur vers Jaeger et sa configuration est cohérente.

**Vérification** : `lab/bin/check 23 15`

<details><summary>Indice 1</summary>

La configuration *all-in-one* de Jaeger 2 (fichier `cmd/jaeger/internal/all-in-one.yaml` du dépôt, à la version 2.22.0) écoute sur `localhost` sauf si `JAEGER_LISTEN_HOST` est défini : dans un pod, le Service ne joindrait rien. Le chart accepte une configuration complète (`userconfig`). `jaeger validate --config <fichier>` la vérifie hors du cluster.
</details>

<details><summary>Indice 2</summary>

Pour retirer une Application et ce qu'elle a créé : le finaliseur `resources-finalizer.argocd.argoproj.io` supprime les ressources gérées avec l'Application. Sans lui, la suppression de l'Application laisse tout en place. Vérifie ensuite qu'il ne reste rien dans l'espace avant de le supprimer.
</details>

**Pour aller plus loin** : Jaeger 2 sait lire d'autres magasins (Elasticsearch/OpenSearch, Cassandra, ClickHouse, ou un magasin distant par gRPC) et propose une interface « Monitor » fondée sur des span metrics : regarde ce qu'il faudrait pour brancher cette vue sur les séries de M23-E13.

---

### M23-E16 — Capacité, rétention et sécurité de la chaîne de traces  `LAB` `★★★`

> **Ticket SEC-2416** — *De : Sophie Laurent, en copie Nadia Roussel*
> Le point d'entrée OTLP `otlp.apps.par1.medisphere.internal` (10.10.41.63) accepte aujourd'hui n'importe quoi, de n'importe qui, en clair. Une trace peut contenir des données de santé : c'est inacceptable. Je veux du TLS signé par notre PKI, une authentification par émetteur, des limites qui empêchent un émetteur fou de faire tomber la plateforme, et des flux réseau fermés dans l'espace `traces`. Nadia veut savoir combien de jours on garde et combien ça pèse.

**Objectifs pédagogiques**
- Sécuriser un récepteur OTLP exposé : TLS (certificat cert-manager renouvelé sans redémarrage), authentification par jeton (`bearertokenauth`), taille des messages bornée.
- Séparer l'entrée interne (agents du cluster) de l'entrée externe, et garder l'équilibrage par `traceID` pour les données qui arrivent de l'extérieur.
- Dimensionner Tempo (rétention, limites d'ingestion, taille de trace, volume du *live-store*) et fermer les flux de l'espace `traces`.

**Prérequis** : M23-E02 (Service 10.10.41.63), M23-E09 (passerelle à deux réplicas, `loadbalancing`), M15 (cert-manager, ClusterIssuer `step-ca-acme`, défi DNS-01, CiliumNetworkPolicy), M20 (`secrets-k8s.sh`).
**Durée indicative** : 3 h.

**Contexte technique**
- Qui envoie de l'extérieur : les VMs du lab (Legacy-RDV au M27, les agents de sécurité au M26…). Pour l'exercice, `adm01` avec la ressource fournie [`ressources/E16-otlp/`](../ressources/E16-otlp/) (une trace OTLP/JSON et un script d'envoi qui lit le jeton dans `~/.config/workbook/otlp-essai.token`).
- Le Collector 0.16x fournit `bearertokenauth` (extension, côté serveur comme côté client ; un fichier de jetons, un par ligne, relu à chaud) et, sur chaque récepteur, `tls` (`cert_file`, `key_file`, `min_version`, `reload_interval`) et `auth.authenticator`. Le contrib n'a pas de processeur de limitation de débit : les limites sont au récepteur (taille des messages) et dans Tempo (`overrides`).
- step-ca émet des certificats ACME de **24 h** par défaut (M15) : cert-manager les renouvelle aux deux tiers de leur durée.
- Le Service 10.10.41.63 est en `externalTrafficPolicy: Local` : l'adresse source réelle reste visible des politiques Cilium.
- Tempo 3.1 : rétention par `tempo.retention` du chart (rendue dans `backend_worker.compaction.block_retention`, 24 h par défaut **dans le chart**) ; limites par `overrides.defaults.ingestion` (`rate_limit_bytes`, `burst_size_bytes`, `max_traces_per_user`) et `overrides.defaults.global.max_bytes_per_trace`.

**Travail demandé**
1. Certificat : un `Certificate` cert-manager pour `otlp.apps.par1.medisphere.internal` dans l'espace `traces` (défi DNS-01). Monte son Secret dans la passerelle et relis-le sans redémarrage.
2. Jetons : un jeton par émetteur (au moins `adm01-essai`), rangés dans Vault `critique` (`secrets/otel.yml`), matérialisés par `secrets-k8s.sh` en Secret `otlp-jetons` monté dans la passerelle. Aucun jeton dans Git.
3. Passerelle : une entrée **interne** (agents, sans TLS, réservée par la CNP) et une entrée **externe** (TLS + jeton, tailles bornées en gRPC et en HTTP) sur d'autres ports, que le Service 10.10.41.63 publie en 4317/4318. Les données externes ne sont pas équilibrées par `traceID` à leur arrivée : fais-les passer par un pipeline qui les renvoie aux réplicas avant l'échantillonnage en queue. Garde `memory_limiter` en tête de chaque pipeline, des lots de taille **maximale** bornée, une file d'attente et des reprises explicites vers Tempo. Valide la configuration hors du cluster (`otelcol-contrib validate`) avant la MR.
4. Essaie depuis `adm01` : sans jeton (refus attendu), avec un mauvais jeton, avec le bon jeton (la trace doit apparaître dans Tempo), avec un message trop gros (refus attendu, lequel ?).
5. Tempo : rétention explicite de **14 jours**, limites d'ingestion et taille maximale de trace explicites, ressources, volume persistant pour le *live-store*. Mesure le volume réel : octets reçus par jour (`tempo_distributor_bytes_received_total`), taille du compartiment `tempo-k8s-par1` (`radosgw-admin bucket stats`), et déduis la taille à 14 jours avec ta marge.
6. Réseau : reprends les CiliumNetworkPolicy d'entrée de M23-E02/E03 (`otel/politiques.yaml`) pour les nouveaux ports de la passerelle, les réseaux du lab qui ont le droit d'émettre (pas seulement MGMT), le renvoi entre réplicas, et ajoute Pyroscope (qui parle à qui, sur quel port ; Prometheus et Grafana compris). Mets à jour les deux matrices de flux. Ajoute les alertes de la chaîne (`regles/`) : perte de spans, refus, file d'attente pleine, plus rien de reçu ; et le tableau **« Pipeline de traces »** (UID `m23-pipeline-traces`, dans `tableaux/`) : ce qui entre dans chaque Collector, ce qui en sort, ce qui se perd et où, remplissage des files, rejets de Tempo.
7. Rédige `docs/observabilite/traces/capacite-securite.md` : dimensionnement chiffré, rétention, limites et ce qu'un émetteur voit quand il les dépasse, gestion des jetons (création, rotation, révocation), flux autorisés, et ce qui reste ouvert (chiffrement interne, sorties).

**Critères de réussite**
- [ ] 10.10.41.63:4317 et :4318 présentent un certificat valide pour `otlp.apps.par1.medisphere.internal`, signé par la racine MédiSphère.
- [ ] Une requête OTLP sans jeton ou avec un jeton inconnu est refusée (401) ; avec le bon jeton, la trace est visible dans Tempo.
- [ ] Aucun jeton dans Git ; tailles de messages bornées ; `memory_limiter` en tête de chaque pipeline.
- [ ] Tempo garde 14 jours, ses limites d'ingestion sont explicites ; les CNP couvrent la passerelle, les agents, Tempo et Pyroscope ; les alertes de la chaîne sont chargées.
- [ ] `capacite-securite.md` donne le dimensionnement chiffré et la procédure de rotation des jetons.

**Vérification** : `lab/bin/check 23 16`

> ⚠️ **Attention** : une CiliumNetworkPolicy d'entrée qui sélectionne un pod le fait passer en **refus par défaut** pour tout ce qu'elle ne liste pas. Avant de pousser les CNP de l'espace `traces`, ouvre `hubble observe -n traces --verdict DROPPED -f` dans un autre terminal, et garde sous la main le retour arrière : `git revert` du commit dans `plateforme/observabilite` (Argo CD resynchronise), ou en urgence `kubectl -n traces delete cnp <nom>` puis le revert (la synchronisation automatique la recréerait sinon).

<details><summary>Indice 1</summary>

L'opérateur accepte `volumes` et `volumeMounts` dans la spécification du `OpenTelemetryCollector`, et il déclare lui-même sur le Service du collector les ports des récepteurs qu'il trouve dans la configuration. L'extension `bearertokenauth` lit un fichier (`filename`) : chaque ligne commence par un jeton, la suite de la ligne est ignorée (un commentaire qui nomme l'émetteur).
</details>

<details><summary>Indice 2</summary>

L'exportateur `loadbalancing` d'une passerelle peut viser le Service sans tête de… cette même passerelle. Les données externes font alors un saut de plus, mais chaque trace finit sur un seul réplica. Pense au port : seule l'entrée interne doit être visée.
</details>

<details><summary>Indice 3</summary>

Pour la mesure : `sum(increase(tempo_distributor_bytes_received_total[1d]))` (Tempo doit être collecté par Prometheus), puis compare avec ce qu'occupe réellement le compartiment après compaction ; les blocs vParquet sont compressés. N'oublie pas les traces gardées à 100 % (erreurs, lentes) : un incident gonfle le volume.
</details>

**Pour aller plus loin** : remplace les jetons statiques par une authentification OIDC (`oidc` du Collector) quand Keycloak arrivera au M24, ou par un TLS mutuel par émetteur ; chiffre aussi les flux internes (agents → passerelle → Tempo) et mesure le coût CPU.

---

### M23-E17 — ADR : traces et profilage  `RED` `★★`

> **Ticket PLAT-2417** — *De : Claire Morel*
> Le comité d'architecture de jeudi doit valider la chaîne de traces et de profils. Écris l'ADR-0230 : ce qu'on a choisi, ce qu'on a écarté et pourquoi, ce que ça coûte, ce qu'on surveille pour revenir sur la décision. Une page et demie, pas un manuel.

**Objectifs pédagogiques**
- Rédiger une décision d'architecture argumentée à partir de mesures (M23-E13 à M23-E16), pas de préférences.
- Expliciter les compromis : instrumentation dans le code ou automatique, échantillonnage en tête ou en queue, stockage objet, multi-signaux.

**Prérequis** : M23-E07 (auto-instrumentation comparée), M23-E09, M23-E13 à M23-E16 ; format des ADR de l'équipe (ADR-0210 du M21, ADR-0220 du M22).
**Durée indicative** : 1 h 30.

**Travail demandé**
Rédige `docs/observabilite/traces/adr/ADR-0230-traces-et-profilage.md` (MR relue par Karim) avec : contexte (exigences HDS, souveraineté, équipes, volumes mesurés) ; décision (OpenTelemetry de bout en bout — SDK dans le code, agents et passerelle, conventions sémantiques ; Tempo sur le RGW ; Pyroscope ; échantillonnage en queue ; Grafana pour la corrélation) ; options écartées et pourquoi (Jaeger, avec ton comparatif ; auto-instrumentation de l'opérateur en production ; échantillonnage seulement en tête ; une solution d'éditeur ; OBI/Beyla en eBPF, gardé en veille) ; conséquences (coûts, compétences, dépendance à Grafana, risques sur les données de santé) ; critères de révision (volumes, version de Tempo, maturité d'OBI).

**Critères de réussite**
- [ ] L'ADR suit le format des ADR de l'équipe (statut, contexte, décision, options, conséquences), cite au moins trois mesures tirées des exercices précédents et au moins quatre options écartées avec leur raison.
- [ ] Il nomme les risques sur les données de santé et la façon dont ils sont traités (masquage, rétention, accès).
- [ ] Il est publié sur `main` de `plateforme/medisphere` (relu par MR).

<details><summary>Indice</summary>

Un bon ADR tient en une phrase de décision, puis justifie. Les options écartées sont crédibles quand elles ont un vrai avantage que tu reconnais (Jaeger : maturité, communauté ; auto-instrumentation : zéro code ; éditeur : support).
</details>

---

### M23-E18 — Questions de production : traces et profilage  `Q` `★★★`

> **Ticket PLAT-2418** — *De : Karim Benali*
> Avant de te laisser l'astreinte de la chaîne de traces, je te pose les questions que je pose en entretien. Réponds par écrit, avec des chiffres quand il y en a.

**Objectifs pédagogiques** : consolider le fonctionnement de production de la chaîne (échantillonnage, perte de données, cardinalité, sécurité, coût) et savoir argumenter.

**Durée indicative** : 1 h 30.

1. L'échantillonnage en tête est réglé à 25 % en production et la passerelle garde en queue les erreurs à 100 %. Quelle proportion des requêtes en erreur retrouves-tu dans Tempo ? Que faut-il changer pour toutes les retrouver, et quel est le prix ?
2. Tu ajoutes un troisième réplica à la passerelle. Que se passe-t-il pour l'échantillonnage en queue pendant les quelques secondes où l'exportateur `loadbalancing` des agents découvre le nouveau réplica ? Comment le mesurer ?
3. Un développeur propose d'ajouter l'identifiant du patient comme attribut de span « pour retrouver ses requêtes ». Donne trois raisons de refuser et deux alternatives qui répondent au besoin.
4. Les span metrics de M23-E13 montrent 12 requêtes/s pour MédiAgenda, les métriques applicatives 95. Lequel des deux chiffres utilises-tu pour un SLO de disponibilité, et pourquoi l'autre ment-il ?
5. La passerelle consomme 900 Mio et redémarre en OOMKilled sous un pic. Classe ces réglages du plus au moins efficace et justifie : limite mémoire du conteneur, `memory_limiter`, `decision_wait` et `num_traces` du `tail_sampling`, taille de la file d'attente de l'exportateur, nombre de réplicas.
6. Tempo répond `RATE_LIMITED` à la passerelle. Que voit l'application ? Que voit la passerelle ? Où sont les données pendant ce temps, et combien de temps avant qu'elles soient perdues ?
7. Pourquoi l'exportateur OTLP vers Tempo ne doit-il pas avoir une file d'attente infinie ? Et pourquoi une file d'attente persistante (sur disque) change-t-elle la réponse ?
8. Une trace de 30 000 spans (un traitement par lots instrumenté span par span) est refusée. Quelle limite a sauté, faut-il la relever, et que proposes-tu à l'équipe ?
9. On te demande de garder les traces un an « pour l'audit HDS ». Que réponds-tu (ce que les traces contiennent, ce que l'audit exige vraiment, ce qui sert déjà à l'audit au M22) ?
10. Le profil CPU de MédiAgenda ne montre rien d'anormal alors que l'API est lente. Cite trois causes de lenteur qu'un profil CPU *on-CPU* ne peut pas montrer, et le signal qui les montre.
11. Compare le coût d'une métrique, d'une ligne de journal, d'une span et d'un profil pour répondre à « l'API est-elle lente depuis 10 h ? ». Lequel interroges-tu en premier, et pourquoi ?
12. Le jeton d'un émetteur externe a fuité dans un ticket. Décris la révocation de bout en bout et le temps pendant lequel l'ancien jeton reste accepté.
13. Pourquoi l'arête « mediagenda-api → medidoc » du graphe de services peut-elle disparaître alors que les deux services fonctionnent ? Donne deux causes côté instrumentation et une côté Collector.
