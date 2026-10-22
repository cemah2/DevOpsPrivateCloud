# Module 23 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- Les configurations ont été validées hors du cluster : `otelcol-contrib validate` (Collector contrib 0.161.0, la version du lab ; configurations de M23-E02 à E16 revalidées à l'harmonisation), `tempo -config.verify` (binaire 3.1.1, sur le rendu du chart 3.2.1 avec les values de M23-E03, E13 et E16), `jaeger validate` (2.22.0), `alloy validate` et `alloy fmt` (1.21.1), `helm template` des charts `tempo` 3.2.1, `pyroscope` 2.4.1 et `jaeger` 4.16.1, `kubeconform` (schémas des CRD OpenTelemetry, Cilium, cert-manager, Argo CD, prometheus-operator), `promtool check rules` (règles et requêtes des tableaux), `go build`/`go vet`/`go test` de MédiDoc avec les correctifs de M23-E06, E08 et E14, `ruff` et `uv lock` de MédiAgenda. Les refus 401 et 400 du point d'entrée ont été observés sur un Collector local avec la même configuration TLS + jeton. **À vérifier sur ton lab** : le comportement réel dans `k8s-par1` (Argo CD, Cilium, RGW).
- Le *metrics-generator* de Tempo 3 en monolithique (exemplars, écriture vers deux réplicas) et la déduplication par Thanos Query de séries écrites à distance.
- Le proxy de sources de Grafana 13 pour Tempo et Pyroscope (utilisé par les checks en lecture) : si ta version le refuse pour ces types de source, les checks concernés passent en échec ; signale-le.
- Pyroscope 2.4 : application de `limits.retention_period` en stockage v2 ; profileur Python sans capacité particulière dans un pod `restricted` ; `HOSTNAME` = nom du nœud dans le DaemonSet Alloy du chart.
- Les volumes, mesures et pourcentages des documents d'exemple sont ceux d'un lab de référence : remplace-les par les tiens.

**Fichiers** : [`fichiers/M23-E13/`](fichiers/M23-E13/) à [`fichiers/M23-E17/`](fichiers/M23-E17/), un dossier par exercice, sous la forme d'un extrait des projets : `observabilite/…` = `plateforme/observabilite`, `gitops/…` = `plateforme/gitops`, `charts-miroir/…`, `mediagenda-api/…` = `mediagenda/api`, `medidoc/…` = `medidoc/medidoc`, `deploiement-mediagenda/…` et `deploiement-medidoc/…` = les dépôts `…/deploiement`, `ansible/…` = `plateforme/ansible`, `medisphere/…` = la documentation. Les `*.extrait.*` sont à fusionner dans le fichier existant (l'emplacement est dit en tête).

---

### M23-E13 — Métriques tirées des traces : graphes de services et RED

**Solution**

*1. Prometheus accepte l'écriture distante, et seulement de Tempo.* Extrait [`kps/values.extrait.yaml`](fichiers/M23-E13/observabilite/kps/values.extrait.yaml) : `prometheus.prometheusSpec.enableRemoteWriteReceiver: true` (l'opérateur ajoute `--web.enable-remote-write-receiver`) ; `exemplar-storage` et `exemplars.maxSize` sont déjà là depuis M23-E08. MR dans `plateforme/observabilite`, synchronisation de l'Application `kube-prometheus-stack`, puis :

```
admin@adm01:~$ kubectl -n supervision get prometheus kps-prometheus -o jsonpath='{.spec.enableRemoteWriteReceiver}{"\n"}'
true
admin@adm01:~$ kubectl -n supervision get pod prometheus-kps-prometheus-0 -o jsonpath='{.spec.containers[?(@.name=="prometheus")].args}' | tr ',' '\n' | grep -E 'remote-write|enable-feature'
"--web.enable-remote-write-receiver"
"--enable-feature=exemplar-storage"
```

Le récepteur ouvert, **tout** client qui joint le port 9090 d'un pod Prometheus peut écrire n'importe quelle série (fausses alertes, cardinalité). [`supervision/cnp-ecriture-tempo.yaml`](fichiers/M23-E13/observabilite/supervision/cnp-ecriture-tempo.yaml) n'ouvre que `POST /api/v1/write` depuis les pods Tempo (règle L7 de Cilium) ; `enableDefaultDeny.ingress: false` empêche cette politique de mettre à elle seule Prometheus en refus par défaut si M21-E29 ne l'a pas déjà fait. Ligne ajoutée à `docs/kubernetes/reseau/matrice-flux-cluster.md` : `traces/tempo → supervision/prometheus 9090 (POST /api/v1/write)`. Le Service 10.10.41.60 vise Thanos Query, qui n'a pas d'API d'écriture : rien à changer de ce côté.

*2. Le metrics-generator.* Extrait [`tempo/values.extrait.yaml`](fichiers/M23-E13/observabilite/tempo/values.extrait.yaml), fusionné dans `tempo/values.yaml` de M23-E03 :
- `tempo.metricsGenerator.enabled: true`, processeurs réglés (`service_graphs` et `span_metrics` : dimension `deployment.environment.name`, seuils d'histogramme d'API web), `registry.external_labels.source: tempo` ;
- `storage.path: /var/tempo/generator` (sur le volume de M23-E03 : le WAL du générateur survit à un redémarrage) ;
- `storage.remote_write` : **deux** cibles, `prometheus-kps-prometheus-0.prometheus-operated.supervision.svc.cluster.local:9090/api/v1/write` et `-1`, chacune avec `send_exemplars: true` ;
- `overrides.defaults.metrics_generator` : `processors: [service-graphs, span-metrics]` (sans eux, le générateur tourne à vide : les processeurs s'activent par locataire), `max_active_series: 20000`, et `trace_id_label_name: trace_id`.

Rendu et vérification **avant** la MR :

```
admin@adm01:~/src/observabilite$ helm template tempo oci://registry.par1.medisphere.internal/charts/tempo --version 3.2.1 \
    -n traces -f tempo/values.yaml | yq 'select(.kind == "ConfigMap" and .metadata.name == "tempo") | .data["tempo.yaml"]' > /tmp/tempo.yaml
admin@adm01:~/src/observabilite$ yq '.metrics_generator.storage.remote_write[].url, .overrides.defaults.metrics_generator' /tmp/tempo.yaml
admin@adm01:~/src/observabilite$ podman run --rm -v /tmp/tempo.yaml:/tempo.yaml:ro,Z \
    registry.par1.medisphere.internal/dockerhub/grafana/tempo:3.1.1 -config.file=/tempo.yaml -config.verify=true
```

`-config.verify` refuse toute clé inconnue (`field bad_key not found in type app.Config`) : c'est le filet contre une clé recopiée d'une autre version. (Les `${AWS_…}` restent vides sans `-config.expand-env`, ce qui ne gêne pas la vérification.)

*3. Explorer.* Après 15 min de charge sur la recette :

```
# Thanos Query (10.10.41.60) ou Explore
count by (__name__) ({__name__=~"traces_(spanmetrics|service_graph)_.*"})
sum by (client, server) (rate(traces_service_graph_request_total[5m]))
sum by (service, span_name) (rate(traces_spanmetrics_calls_total{span_kind="SPAN_KIND_SERVER"}[5m]))
count({__name__=~"traces_.*"})
```

Nœuds du graphe qui ne sont pas des services instrumentés : la base (nœud « virtuel » nommé d'après `db.namespace`/`db.name` ou `db.system.name`, ici `mediagenda`), Valkey (`redis`), le stockage S3 de MédiDoc, et `user` comme client des requêtes venues de la Gateway (pas de span parente). Le premier facteur de cardinalité est `span_name` : nos instrumentations nomment les spans serveur d'après la **route** (`GET /api/v1/rendez-vous/{rdv_id}`), jamais d'après le chemin réel.

*4. Source Grafana.* Dans la ConfigMap `sources-tempo` (M23-E03/E08), ajoute au `jsonData` de `Tempo` les clés de [`grafana/source-tempo.extrait.yaml`](fichiers/M23-E13/observabilite/grafana/source-tempo.extrait.yaml) : `serviceMap.datasourceUid: prometheus` (onglet *Service Graph* d'Explore et vue en nœuds de la trace), `tracesToMetrics` (requêtes RED depuis une span, avec `$$__tags` : `$$` parce que le *sidecar* passe le fichier par l'interpolation de variables d'environnement du provisionnement de Grafana, où `$$` produit un `$`). `tracesToProfiles` est pour M23-E14.

*5. Tableau et règles.* [`tableaux/mediagenda-red-traces.json`](fichiers/M23-E13/observabilite/tableaux/mediagenda-red-traces.json) (UID `m23-red-traces`, variable `${datasource}`, variable `env`) : débit, part vue par les traces, erreurs et p95 des deux sources, appels sortants et latence des arêtes. Règles d'enregistrement [`regles/traces-red.yaml`](fichiers/M23-E13/observabilite/regles/traces-red.yaml) (`service:traces_spanmetrics_appels:taux5m`…) : la CI de `plateforme/observabilite` (M21) les passe à `promtool check rules`.

*6. L'écart expliqué* : [`metriques-depuis-traces.md`](fichiers/M23-E13/medisphere/docs/observabilite/traces/metriques-depuis-traces.md). L'essentiel : avec 100 % des erreurs et des lentes et 10 % du reste, les span metrics sous-estiment le débit d'un facteur proche de 10, **surestiment** le taux d'erreurs et la latence. Elles servent au graphe de services, au RED des dépendances et aux exemplars ; jamais aux SLO.

**Explications**

Le *metrics-generator* consomme les spans au moment où Tempo les reçoit (en monolithique, le distributeur les lui passe dans le même processus ; en microservices, il lit Kafka). Pour une arête, il apparie la span **client** d'un service et la span **serveur** du service appelé (même trace, parent-enfant) pendant `wait` (10 s) : une arête dont il ne voit qu'un côté est comptée dans `traces_service_graph_unpaired_spans_total`, et une dépendance non instrumentée devient un nœud virtuel grâce aux `peer_attributes`. Les séries sont tenues dans un registre en mémoire et écrites toutes les `collection_interval` (15 s) ; une série inactive pendant `stale_duration` (15 min) disparaît. Les spans plus vieilles que `metrics_ingestion_time_range_slack` (30 s) sont **ignorées** : si la passerelle met plus de 30 s à livrer (file d'attente pleine, Tempo lent), les métriques sous-comptent en silence.

Pourquoi deux cibles d'écriture : chaque réplica de Prometheus est une base indépendante ; Thanos Query déduplique à la lecture des séries **identiques** venues de réplicas différents. Une écriture équilibrée par un Service donnerait à chaque réplica un échantillon sur deux, des séries différentes et trouées.

**Alternatives**

- Le connecteur `spanmetrics` (et `servicegraph`) du Collector, dans un pipeline de la passerelle **avant** `tail_sampling` : RED exact, mais les séries passent par la passerelle (cardinalité, mémoire) et il faut un exportateur Prometheus ou une écriture distante de plus. À réserver aux services sans métriques propres.
- Les requêtes de **métriques TraceQL** de Tempo (`{…} | rate() by (…)`), calculées à la demande sur les traces stockées : aucune série permanente, mais lentes sur de longues périodes et elles aussi biaisées par l'échantillonnage.
- Écrire dans un récepteur unique (Thanos Receive, Mimir) : c'est l'architecture « push » que l'ADR-0210 a écartée.

**Pièges classiques**
- Viser le Service `kps-prometheus` : séries trouées, courbes en dents de scie selon le réplica que choisit Thanos Query.
- Oublier `overrides.defaults.metrics_generator.processors` : le générateur est actif mais ne produit rien.
- Exemplars sans lien : Tempo nomme l'étiquette `traceID` par défaut, Grafana attend `trace_id` depuis M23-E08 (`exemplarTraceIdDestinations`) ; aligner par `trace_id_label_name`.
- Une span nommée avec un identifiant (`span.update_name(f"rdv {id}")`) : une série par rendez-vous ; le garde-fou `max_active_series` coupe alors **toutes** les nouvelles séries, pas seulement les fautives.
- Construire un SLO ou une alerte de débit sur `traces_spanmetrics_*`.
- Ouvrir le récepteur d'écriture sans CNP : n'importe quel pod du cluster peut injecter des séries.

**En production chez MédiSphère**

Alerte sur `tempo_metrics_generator_registry_series_limited_total` (cardinalité atteinte) et sur `tempo_metrics_generator_registry_active_series` rapporté à la limite (`max_active_series`) ; suivi des échecs d'écriture distante du générateur dans ses journaux et ses métriques internes. Revue de cardinalité trimestrielle avec le rapport `count by (__name__)`. Le graphe de services sert aux revues d'architecture : il révèle les dépendances non documentées (un service qui appelle directement la base d'un autre).

---

### M23-E14 — Profilage continu avec Pyroscope

**Solution**

*1. Stockage, identités, chart.* Sur `ceph01`, comme pour Tempo en M23-E03 :

```
admin@ceph01:~$ sudo cephadm shell -- radosgw-admin user create --uid=pyroscope --display-name="Pyroscope k8s-par1" --max-buckets=1
admin@ceph01:~$ sudo cephadm shell -- radosgw-admin quota set --quota-scope=user --uid=pyroscope --max-size=10G
admin@ceph01:~$ sudo cephadm shell -- radosgw-admin quota enable --quota-scope=user --uid=pyroscope
```

Le compartiment `pyroscope-k8s-par1` est créé avec l'identité `pyroscope` (`aws s3 mb`) ; les clés vont dans Vault `critique` (`secrets/pyroscope.yml`), `secrets-k8s.sh pyroscope` en fait le Secret `traces/pyroscope-objstore` (clés `S3_CLE`, `S3_SECRET`). Pour les checks, une seconde identité en **lecture** (sous-utilisateur ou politique de compartiment en lecture) dans `~/.config/workbook/s3-pyroscope.env` (600). Le chart s'ajoute à `charts.yaml` de `plateforme/charts-miroir` ([extrait](fichiers/M23-E14/charts-miroir/charts.extrait.yaml)) avec son empreinte relevée puis vérifiée.

*2. Pyroscope.* [`pyroscope/values.yaml`](fichiers/M23-E14/observabilite/pyroscope/values.yaml) et l'Application [`pyroscope`](fichiers/M23-E14/gitops/plateforme/pyroscope.yaml). Points clés : `structuredConfig` (stockage S3 du RGW, `bucket_lookup_type: path`, `${S3_CLE}` avec `config.expand-env`), `SSL_CERT_DIR` qui ajoute la racine MédiSphère (ConfigMap `racine-medisphere` de l'espace, M23-E02) aux répertoires de CA lus par Go, `limits.retention_period: 14d`, volume persistant, **`alloy.enabled: false`** (le chart déploie sinon un second Alloy qui profilerait les pods annotés), ServiceMonitor étiqueté pour kps. Avant la MR :

```
admin@adm01:~/src/observabilite$ helm template pyroscope oci://registry.par1.medisphere.internal/charts/pyroscope --version 2.4.1 \
    -n traces -f pyroscope/values.yaml | yq 'select(.kind == "ConfigMap" and .metadata.name == "pyroscope-config") | .data'
admin@adm01:~/src/observabilite$ helm template … | grep -c 'kind: StatefulSet'     # 1 : Pyroscope seul, pas d'Alloy
```

*3. MédiAgenda.* MR dans `mediagenda/api`, sur l'état laissé par M22-E06, M23-E04, E06 et E08 : `uv add "pyroscope-io>=1.4.0,<2" "pyroscope-otel>=1.1.0,<2"` (roues manylinux pour Python 3.13, `uv.lock` régénéré), puis le correctif [`profilage.patch`](fichiers/M23-E14/mediagenda-api/profilage.patch) : module [`profilage.py`](fichiers/M23-E14/mediagenda-api/src/mediagenda/profilage.py) et, dans `__main__.py`, juste après `telemetrie.configurer(settings.version)` (M23-E04) :

```python
    profilage.configurer_profilage(settings.version)
```

Le profileur ne démarre que si `MEDIAGENDA_PYROSCOPE_URL` est définie (tests et poste local intacts : `uv run pytest` reste vert), prend `OTEL_SERVICE_NAME` comme nom (`mediagenda-api`), étiquette `version` et `environnement`, et branche `PyroscopeSpanProcessor` sur le fournisseur de traces. L'adresse vient du composant [`components/profilage`](fichiers/M23-E14/deploiement-mediagenda/components/profilage/kustomization.yaml) de `mediagenda/deploiement` : un `configMapGenerator` qui fusionne dans `mediagenda-parametres` (déjà dans `envFrom` depuis M17-E09), donc valable pour le Deployment de dev comme pour le Rollout de recette et de production. Promotion : dev, puis recette.

*4. MédiDoc et Alloy.* MR dans `medidoc/medidoc` : [`profilage.patch`](fichiers/M23-E14/medidoc/profilage.patch) (à appliquer après les correctifs de M23-E06 puis E08 ; paquet [`internal/profilage`](fichiers/M23-E14/medidoc/internal/profilage/profilage.go), appel dans `main.go`, `godeltaprof` v0.1.12) : un serveur `pprof` **séparé**, sur `MEDIDOC_PPROF_ADDR` (`:6060`), avec `net/http/pprof` et les profils delta de `godeltaprof` ; taux d'échantillonnage des verrous et des blocages modérés. Dans `medidoc/deploiement`, [`components/profilage`](fichiers/M23-E14/deploiement-medidoc/components/profilage/kustomization.yaml) ajoute la variable et le port de conteneur **nommé** `pprof`, sans Service. Côté plateforme, [`alloy/profils-medidoc.alloy`](fichiers/M23-E14/observabilite/alloy/profils-medidoc.alloy) s'ajoute à `config.alloy` : `discovery.kubernetes` limité aux espaces de MédiDoc **et au nœud de l'instance** (`spec.nodeName=` + `sys.env("HOSTNAME")`), `discovery.relabel` qui garde le port `pprof` et pose `service_name="medidoc"`, `pyroscope.scrape` (CPU, delta mémoire, verrous, blocages, goroutines ; profils non delta désactivés), `pyroscope.write` vers `pyroscope.traces.svc:4040`. Vérifié avec `alloy fmt` et `alloy validate`. Le flux Alloy → 6060 : [`alloy/cnp-pprof-medidoc.yaml`](fichiers/M23-E14/observabilite/alloy/cnp-pprof-medidoc.yaml), avec `enableDefaultDeny.ingress: false` pour ne pas changer le régime des pods de MédiDoc. Le flux MédiAgenda → Pyroscope 4040 demande une **sortie** (les espaces de MédiAgenda sont en refus par défaut, M15/M17) : politique de cluster [`otel/profils-vers-pyroscope.yaml`](fichiers/M23-E14/observabilite/otel/profils-vers-pyroscope.yaml), sur le modèle de `telemetrie-vers-otel-agent` (M23-E02), ajoutée à `otel/kustomization.yaml` ; l'**entrée** côté Pyroscope est la CNP `traces-pyroscope` de l'espace `traces` (M23-E16).

*5. Sources et lien.* [`grafana/sources-pyroscope.yaml`](fichiers/M23-E14/observabilite/grafana/sources-pyroscope.yaml) (uid `pyroscope`, type `grafana-pyroscope-datasource`) ; `tracesToProfiles` dans la source Tempo ([extrait](fichiers/M23-E13/observabilite/grafana/source-tempo.extrait.yaml) : `service.name` → `service_name`, type `process_cpu:cpu:nanoseconds:cpu:nanoseconds`). Depuis une span de MédiAgenda, « Profiles for this span » ouvre le profil du service sur la période de la span.

*6. Lecture et surcoût* : [`profilage.md`](fichiers/M23-E14/medisphere/docs/observabilite/traces/profilage.md). Mesure du surcoût, à charge égale (outil de M21-E23) :

```
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="mediagenda-recette", container="api"}[5m]))
sum by (pod) (container_memory_working_set_bytes{namespace="mediagenda-recette", container="api"})
```

une fois avec `MEDIAGENDA_PYROSCOPE_URL`, une fois sans (variable retirée du composant le temps de la mesure, par MR). Contrôle des profils reçus :

```
admin@adm01:~$ kubectl -n traces port-forward svc/pyroscope 4040 &
admin@adm01:~$ curl -s -X POST -H 'Content-Type: application/json' \
    -d "{\"name\": \"service_name\", \"start\": $(( ($(date +%s) - 3600) * 1000 )), \"end\": $(date +%s)000}" \
    http://127.0.0.1:4040/querier.v1.QuerierService/LabelValues
{"names":["medidoc","mediagenda-api","pyroscope"]}
```

**Explications**

Deux modes de collecte. *Push* (MédiAgenda) : le SDK échantillonne la pile du processus 100 fois par seconde (pour Python, un échantillonneur à la py-spy, en Rust, qui lit la mémoire de son propre processus) et envoie toutes les 10 s. *Pull* (MédiDoc) : le runtime Go sait produire ses profils (`pprof`), Alloy les demande (`/debug/pprof/profile?seconds=…` pour le CPU, les profils delta pour le tas), ce qui ne demande **aucune** dépendance au service de profils dans l'image. Les profils delta (`godeltaprof`) envoient la différence depuis la collecte précédente au lieu d'un cumul depuis le démarrage : moins de volume et pas de calcul de différence côté serveur.

Pyroscope 2 (stockage v2) écrit des segments dans le stockage objet et indexe les métadonnées dans un *metastore* (Raft) : le stockage objet n'est plus facultatif, et le volume local porte le métastore.

**Alternatives**

- Profiler MédiDoc en *push* avec `pyroscope-go` dans le code : lien span → profil possible en Go (`otel-profiling-go`), mais une dépendance de plus dans l'application.
- Profilage eBPF de tous les processus d'un nœud (Alloy `pyroscope.ebpf`, OBI) : aucune modification des applications, des symboles parfois incomplets (Python interprété), et des privilèges élevés sur les nœuds : à revoir au M26.
- Garder un seul profil ponctuel (`py-spy dump`, `go tool pprof` en direct) : utile en incident, inutile pour comparer « avant » et « après ».

**Pièges classiques**
- Laisser l'Alloy du chart Pyroscope activé : un deuxième DaemonSet de collecte, des profils en double.
- Publier `pprof` sur le port de l'API ou par un Service : `/debug/pprof/` révèle la ligne de commande et l'environnement du processus et permet de le charger (profil CPU de 60 s à la demande).
- Un `service_name` différent du `service.name` des traces : le lien Tempo → Pyroscope ouvre un profil vide.
- Démarrer le profileur Python avant un `fork` (uvicorn `--workers`) : blocages possibles du processus enfant.
- Conclure d'un *flame graph* *on-CPU* qu'une requête est rapide : une attente de 800 ms sur PostgreSQL n'y apparaît pas.
- Chaque instance d'Alloy du DaemonSet collecte tous les pods si on ne filtre pas sur le nœud : profils comptés trois fois.

**En production chez MédiSphère**

Profils de production gardés 14 jours, comme les traces ; surcoût surveillé (CPU des pods comparé au trimestre précédent) ; le profil est une pièce du post-mortem de chaque incident de performance (M23-E23). La donnée sensible d'un profil est le **code** (noms de fonctions, chemins) et éventuellement des étiquettes : jamais d'étiquette avec un identifiant métier.

---

### M23-E15 — Jaeger v2 en comparaison

**Solution**

*1. Déploiement.* Chart recopié (`jaeger` 4.16.1, Jaeger 2.22.0, [entrée de `charts.yaml`](fichiers/M23-E15/charts-miroir/charts.extrait.yaml)), [`jaeger-essai/values.yaml`](fichiers/M23-E15/observabilite/jaeger-essai/values.yaml) et Application [`jaeger-essai`](fichiers/M23-E15/gitops/plateforme/jaeger-essai.yaml) (`CreateNamespace=true`, finaliseur de ressources). La configuration *all-in-one* intégrée écoute sur `localhost` sauf si `JAEGER_LISTEN_HOST` est défini : le corrigé fournit une configuration complète (`userconfig`, montée par le chart et passée par `--config`) qui écoute sur `0.0.0.0`, limite la mémoire à 20 000 traces et ne garde que l'OTLP. Vérification hors du cluster :

```
admin@adm01:~/m23/e15$ yq '.userconfig' jaeger-essai/values.yaml > jaeger.yaml && ./jaeger validate --config jaeger.yaml
```

(`jaeger` extrait de l'image `jaegertracing/jaeger:2.22.0` ; la commande `validate` est celle du Collector OpenTelemetry sur lequel Jaeger 2 est construit.)

*2. Double export.* [Extrait de la passerelle](fichiers/M23-E15/observabilite/otel/otel-passerelle.essai-jaeger.extrait.yaml) : exportateur `otlp_grpc/jaeger` avec sa propre file et des reprises courtes, ajouté au pipeline `traces` après l'échantillonnage. Indépendance des deux destinations :

```
admin@adm01:~$ kubectl -n jaeger-essai scale deploy jaeger --replicas=0; sleep 60; kubectl -n jaeger-essai scale deploy jaeger --replicas=1
# Thanos Query, pendant la minute :
sum by (exporter) (rate({__name__=~"otelcol_exporter_sent_spans(_total)?", job=~".*otel-passerelle.*"}[1m]))
max by (exporter) (otelcol_exporter_queue_size{job=~".*otel-passerelle.*"})
```

L'exportateur Tempo continue d'envoyer ; la file de `otlp_grpc/jaeger` monte puis se vide au retour (Argo CD remet `replicas: 1` de toute façon avec `selfHeal`).

*3-4. Comparaison* : [`comparatif-jaeger.md`](fichiers/M23-E15/medisphere/docs/observabilite/traces/comparatif-jaeger.md). Interface de Jaeger : `kubectl -n jaeger-essai port-forward svc/jaeger 16686` puis `http://127.0.0.1:16686` depuis `adm01`. La requête structurelle qui fait la différence : `{resource.service.name = "mediagenda-api" && kind = client} >> {resource.service.name = "medidoc" && duration > 200ms}` n'a pas d'équivalent dans la recherche de Jaeger.

*5. Retrait.* Dans cet ordre : retirer l'exportateur et sa référence du pipeline (MR dans `plateforme/observabilite`) ; supprimer `plateforme/jaeger-essai.yaml` de `plateforme/gitops` (l'application racine, avec `prune`, supprime l'Application ; le finaliseur supprime ce qu'elle a créé) ; vérifier que l'espace est vide puis le supprimer (Argo CD ne supprime pas un espace qu'il a créé par `CreateNamespace`) ; retirer le chart de `charts.yaml` si l'équipe ne veut pas le garder en miroir ; enfin vérifier les métriques :

```
admin@adm01:~$ kubectl get all,cm,secret -n jaeger-essai          # rien
admin@adm01:~$ kubectl delete namespace jaeger-essai
sum(rate({__name__=~"otelcol_exporter_send_failed_spans(_total)?"}[10m]))   # 0
```

**Explications**

Jaeger 2 a abandonné ses propres agents et collecteurs : c'est une distribution du Collector OpenTelemetry avec des extensions de stockage et de requête. La différence avec Tempo n'est donc plus la réception (même OTLP) mais le **stockage** (Jaeger indexe tout dans une base de recherche ; Tempo écrit des blocs Parquet dans du stockage objet et ne garde qu'un index minimal) et la **requête** (recherche par champs contre TraceQL).

**Alternatives**

Garder Jaeger comme interface sur les données de Tempo (Tempo expose une API compatible, `tempo-query`) : utile pour une équipe habituée à son interface, sans second stockage. Comparer aussi SigNoz ou une pile ClickHouse : même famille « base de colonnes », à exploiter.

**Pièges classiques**
- Ajouter l'exportateur Jaeger **avant** l'échantillonnage en queue (dans un autre pipeline) : Jaeger reçoit 100 % du trafic et la comparaison des volumes est faussée.
- Partager une file d'attente entre les deux destinations (un seul exportateur en `loadbalancing`, par exemple) : une destination lente pénalise l'autre.
- Supprimer l'Application sans finaliseur, ou par `--cascade=false` : le Deployment et le Service restent, orphelins.
- Oublier la passerelle : l'exportateur vers un Service disparu remplit sa file et gonfle `otelcol_exporter_send_failed_spans` pendant des jours.

**En production chez MédiSphère**

Tout essai a sa date de fin dans le ticket et son retrait vérifié par un check (ici, M23-E15 et le mini-projet). Le comparatif reste dans `docs/` : c'est lui qu'on relira si la décision est remise en cause (ADR-0230, critères de révision).

---

### M23-E16 — Capacité, rétention et sécurité de la chaîne de traces

**Solution**

*1. Certificat.* [`otel/certificat-otlp.yaml`](fichiers/M23-E16/observabilite/otel/certificat-otlp.yaml) : `Certificate` `otlp-externe` (Secret `otlp-externe-tls`), ClusterIssuer `step-ca-acme`, défi **DNS-01** (le nom n'est pas servi par la Gateway).

```
admin@adm01:~$ kubectl -n traces get certificate otlp-externe
NAME           READY   SECRET             AGE
otlp-externe   True    otlp-externe-tls   2m
```

*2. Jetons.* Structure de Vault : [`secrets/otel.yml.exemple`](fichiers/M23-E16/ansible/secrets/otel.yml.exemple) ; jeton créé par `openssl rand -hex 32` ; `secrets-k8s.sh otel` produit `traces/otlp-jetons` (clé `jetons` : « `<jeton> adm01-essai` » par ligne). Sur `adm01`, le jeton d'essai dans `~/.config/workbook/otlp-essai.token` (600).

*3. Passerelle.* [`otel/otel-passerelle.yaml`](fichiers/M23-E16/observabilite/otel/otel-passerelle.yaml) (remplace la version de M23-E09) :
- volumes : `otlp-externe-tls` et `otlp-jetons` montés en lecture ;
- extension `bearertokenauth/externe` (`filename`) ;
- récepteur `otlp` interne (4317/4318, tailles bornées) et `otlp/externe` (14317/14318, `tls` avec `reload_interval: 1h`, `auth.authenticator`, 4 Mio par message ou requête) ;
- pipeline `traces/externe` : `memory_limiter` puis exportateur `loadbalancing/passerelle` vers le Service sans tête de **la passerelle elle-même**, port 4317 (son résolveur `k8s` lit les EndpointSlices : Role et RoleBinding [`otel/rbac-passerelle.yaml`](fichiers/M23-E16/observabilite/otel/rbac-passerelle.yaml) pour le compte `otel-passerelle-collector` que l'opérateur crée, ajoutés à `otel/kustomization.yaml`) ; pipeline `traces` inchangé (`memory_limiter`, `tail_sampling`, `batch` borné à 2 048 spans, `otlp_grpc/tempo` avec file et reprises).

Le Service [`otlp-externe`](fichiers/M23-E16/observabilite/otel/service-otlp-externe.yaml) garde 4317/4318 vers l'extérieur et vise 14317/14318. Validation avant la MR :

```
admin@adm01:~/src/observabilite$ yq '.spec.config' otel/otel-passerelle.yaml > /tmp/passerelle.yaml
admin@adm01:~/src/observabilite$ ~/m23/otelcol-contrib validate --config /tmp/passerelle.yaml && echo valide
valide
```

(`validate` ne lit ni les certificats ni le fichier de jetons : il vérifie la structure, les noms et les pipelines.)

*4. Essais depuis `adm01`* avec [`ressources/E16-otlp/envoyer-trace.sh`](../ressources/E16-otlp/envoyer-trace.sh) :

```
admin@adm01:~/DevOpsPrivateCloud/modules/23-traces/ressources/E16-otlp$ ./envoyer-trace.sh --sans-jeton
HTTP 401 — trace afd89e8980573a88d3fd1485bf23833e
{"code":16,"message":"missing or empty authorization header: Authorization"}
admin@adm01:…/E16-otlp$ ./envoyer-trace.sh --jeton-fichier /tmp/faux.token
HTTP 401 — trace 4a5d4d60aecb181dc038b9223b312282
{"code":16,"message":"provided authorization does not match expected scheme or token"}
admin@adm01:…/E16-otlp$ ./envoyer-trace.sh
HTTP 200 — trace 012cf1fe3b655d5bc103d356bf9e52a3
{"partialSuccess":{}}
admin@adm01:…/E16-otlp$ ./envoyer-trace.sh --gros
HTTP 400 — trace 2e1cd358e5e951f018b85fa4903f2d03
{"code":3,"message":"http: request body too large"}
admin@adm01:~$ openssl s_client -connect 10.10.41.63:4317 -servername otlp.apps.par1.medisphere.internal \
    -verify_hostname otlp.apps.par1.medisphere.internal -verify_return_error \
    -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt </dev/null 2>&1 | grep 'Verify return code'
Verify return code: 0 (ok)
```

La trace `012cf1…` (service `adm01-essai`) apparaît dans Tempo après l'attente de décision (une dizaine de secondes) — à condition qu'elle soit gardée par l'échantillonnage : elle n'est ni en erreur ni lente, elle a 10 % de chances. Pour la voir à coup sûr, envoie-en une dizaine, ou pose le statut d'erreur dans la trace modèle (`"status": {"code": 2}`).

*5. Tempo.* [`tempo/values.extrait.yaml`](fichiers/M23-E16/observabilite/tempo/values.extrait.yaml) : rétention explicite 336 h (déjà posée en M23-E03, gardée explicite), `overrides.defaults.ingestion` (`rate_limit_bytes`, `burst_size_bytes`, `max_traces_per_user`), `overrides.defaults.global.max_bytes_per_trace`, ressources ; le volume de M23-E03 n'est pas changé dans les values (gabarit de StatefulSet immuable). Mesures :

```
sum(increase(tempo_distributor_bytes_received_total[1d]))
admin@ceph01:~$ sudo cephadm shell -- radosgw-admin bucket stats --bucket=tempo-k8s-par1 | jq '.usage["rgw.main"] | {size_kb_actual, num_objects}'
admin@ceph01:~$ sudo cephadm shell -- radosgw-admin quota set --quota-scope=user --uid=tempo --max-size=50G && sudo cephadm shell -- radosgw-admin quota enable --quota-scope=user --uid=tempo
```

*6. Réseau et alertes.* [`otel/politiques.yaml`](fichiers/M23-E16/observabilite/otel/politiques.yaml) remplace celle de M23-E03 : entrée externe sur 14317/14318 depuis 10.10.0.0/16, renvoi entre réplicas sur 4317, Pyroscope couvert. Avant de pousser, dans un second terminal :

```
admin@adm01:~$ hubble observe -n traces --verdict DROPPED -f
```

Rien ne doit apparaître après la synchronisation, à part des essais volontaires. Alertes : [`regles/traces-collectors.yaml`](fichiers/M23-E16/observabilite/regles/traces-collectors.yaml) (`CollectorPerdDesSpans`, `CollectorRefuseDesSpans`, `CollectorFileDAttentePleine`, `TracesAbsentes`), passées à `promtool check rules` dans la CI, et le tableau [`tableaux/traces-pipeline.json`](fichiers/M23-E16/observabilite/tableaux/traces-pipeline.json) (« Pipeline de traces », UID `m23-pipeline-traces`) qui met côte à côte entrées, sorties, pertes, files et rejets de Tempo. Matrices : `docs/socle/matrice-flux.md` (réseaux du lab → 10.10.41.63:4317-4318, déjà prévu au PLAN) et `docs/kubernetes/reseau/matrice-flux-cluster.md` (tableau des entrées de l'espace `traces`).

*7.* [`capacite-securite.md`](fichiers/M23-E16/medisphere/docs/observabilite/traces/capacite-securite.md).

**Explications**

- **Pourquoi deux entrées** : les agents du cluster ont déjà routé chaque trace vers le bon réplica (`loadbalancing`, M23-E09) ; ce qui arrive de l'extérieur passe par le Service LoadBalancer, qui répartit **par connexion**. Sans renvoi par `traceID`, une trace d'un émetteur externe pourrait être échantillonnée en queue sur deux réplicas, chacun avec une partie. Le pipeline `traces/externe` fait ce renvoi, puis les données rejoignent l'entrée interne d'un réplica.
- **Rechargement sans redémarrage** : le kubelet met à jour les fichiers d'un Secret monté (sans `subPath`) en une à deux minutes ; le récepteur relit son certificat tous les `reload_interval`, l'extension relit le fichier de jetons quand il change.
- **Rafale et débit** : le limiteur de Tempo est un seau à jetons ; `rate_limit_bytes` le remplit, `burst_size_bytes` est sa taille. Une requête plus grosse que le seau n'est jamais acceptée, quel que soit le débit : d'où la borne sur les lots de la passerelle (M23-E21).

**Alternatives**

- TLS mutuel par émetteur (certificats clients signés par `ca01`, `client_ca_file`) : plus fort qu'un jeton, plus lourd à distribuer ; ou OIDC (extension `oidc`) quand Keycloak arrivera (M24).
- Un Collector dédié à l'entrée externe (ni agent ni passerelle) qui ne fait qu'authentifier et renvoyer : séparation plus nette, une charge de plus.
- Limiter le débit par émetteur : pas de processeur dans le contrib ; Tempo limite par locataire. Un locataire Tempo par émetteur externe (multi-locataire activé) donnerait des limites par émetteur.

**Pièges classiques**
- Oublier les droits du résolveur `k8s` pour le compte de la **passerelle** : ceux des agents (M23-E09) ne valent que pour `otel-agent` ; la liste de réplicas de la passerelle reste vide et tout ce qui entre par 10.10.41.63 est perdu.
- `reload_interval` de 24 h avec des certificats de 24 h : la passerelle sert un certificat expiré pendant des heures.
- Jeton dans `token:` en clair dans Git ; ou passé à `curl -H "Authorization: Bearer …"` (visible dans `ps` et l'historique) : le script fourni le passe par un fichier.
- Un `bearertokenauth` sans TLS : le jeton circule en clair (l'extension le dit elle-même dans sa documentation).
- Une CNP d'entrée posée sans inventaire des flux : Prometheus ne collecte plus les Collectors, Grafana ne joint plus Tempo, et le silence des métriques passe pour une panne de la chaîne.
- Changer `persistence.size` d'un StatefulSet dans les values : synchronisation refusée (gabarit de volume immuable).
- Croire que `max_recv_msg_size_mib` protège la mémoire : il borne **un** message ; c'est `memory_limiter` qui protège le processus.

**En production chez MédiSphère**

Rotation des jetons tous les 90 jours (rappel planifié), inventaire des émetteurs dans `capacite-securite.md`, alerte sur l'expiration du certificat (cert-manager l'expose : `certmanager_certificate_expiration_timestamp_seconds`), revue trimestrielle du volume et des quotas. Au M26 : chiffrement interne et filtrage des sorties de l'espace `traces`.

---

### M23-E17 — ADR : traces et profilage

**Solution**

Exemple : [`ADR-0230-traces-et-profilage.md`](fichiers/M23-E17/medisphere/docs/observabilite/traces/adr/ADR-0230-traces-et-profilage.md). Ce qui fait un bon ADR ici :
- une décision en une phrase, puis des **mesures** (volume reçu et stocké, surcoût du profilage, mémoire de Jaeger contre Tempo) ;
- des options écartées présentées avec leur vrai avantage (Jaeger est plus simple, l'auto-instrumentation ne coûte aucune ligne de code) et la raison précise de l'écarter ;
- les données de santé traitées explicitement (masquage dans l'agent, rétention de 14 jours, accès par Grafana seulement, contrôle reproductible) ;
- des critères de révision mesurables (volume, mode microservices de Tempo 3 avec Kafka, maturité d'OBI).

**Explications**

Un ADR ne décrit pas l'installation (c'est le rôle du `README.md` et des runbooks) : il garde la trace du **pourquoi**, pour qu'une personne qui arrive dans deux ans comprenne ce qui serait cassé si l'on changeait d'avis.

**Pièges classiques**
- Un ADR écrit comme une brochure (« Tempo est scalable et performant ») : aucune mesure, aucun compromis.
- Oublier ce qui rend la décision réversible : l'instrumentation OpenTelemetry, indépendante du stockage.
- Ne pas dire ce qu'on a refusé de faire (traces de 1 an, attributs patients) : c'est ce que l'auditrice HDS lira en premier.

**En production chez MédiSphère**

L'ADR est relu par le comité, accepté par MR, et cité par les tickets qui en découlent ; il est révisé (nouveau numéro qui remplace l'ancien) si un critère de révision est atteint.

---

### M23-E18 — Questions de production : traces et profilage

1. **Erreurs retrouvées** : 25 % seulement. L'échantillonnage en tête décide au début de la requête, avant de savoir qu'elle échouera ; les 75 % non échantillonnées ne sont jamais émises, la passerelle ne peut pas les garder. Pour toutes les retrouver : tout émettre en tête (ratio 1.0, comme en dev) et laisser la passerelle réduire en queue. Prix : tout le volume traverse le réseau, les agents et la passerelle (mémoire du `tail_sampling` proportionnelle au débit × `decision_wait`). Une voie intermédiaire : l'échantillonnage en tête par `tracestate` cohérent, mais il ne résout pas le problème des erreurs.
2. **Troisième réplica** : chaque agent découvre le nouveau réplica (résolveur `k8s`, quelques secondes) et recalcule le hachage cohérent ; pendant la bascule, des agents différents peuvent router une même trace différemment, et une trace en cours peut avoir ses premières spans sur un réplica et les suivantes sur le nouveau : quelques traces coupées ou mal décidées, sur la durée de `decision_wait`. Mesure : traces enracinées hors de leur service d'entrée (`{trace:rootService = "medidoc"}`), `otelcol_processor_tail_sampling_*` par réplica, et les spans orphelines avant et après l'ajout.
3. **Identifiant de patient** : (a) c'est une donnée de santé indirecte (relie une personne à un soin), qui sortirait du périmètre de l'application vers la plateforme d'observabilité, accessible à d'autres équipes et gardée 14 jours ; (b) la cardinalité (un index, une colonne dédiée potentielle) ; (c) les traces sont copiées (sauvegardes, essais, export) sans les contrôles de la base. Alternatives : un identifiant **technique** de rendez-vous (`mediagenda.rendez_vous.id`, déjà posé en M23-E06), qui ne mène au patient qu'avec un accès à la base ; ou une recherche par `trace_id` journalisé côté application avec les droits de l'application ; à défaut, un pseudonyme (HMAC avec une clé de l'application) si l'équipe a vraiment besoin de regrouper par patient.
4. **12 contre 95 req/s** : le SLO se calcule sur les **métriques applicatives** (95 req/s) : elles comptent chaque requête. Les span metrics comptent les spans **gardées** par l'échantillonnage (environ 10 % du normal, toutes les erreurs) : leur débit est faux, leur taux d'erreurs gonflé.
5. **OOMKilled** : du plus au moins efficace : (1) `memory_limiter` réglé en pourcentage de la limite du conteneur (refuse **avant** l'OOM, l'émetteur réessaie) ; (2) `num_traces` et `decision_wait` du `tail_sampling` (ce sont eux qui remplissent la mémoire : débit × attente) ; (3) le nombre de réplicas (répartit les traces) ; (4) la limite mémoire du conteneur (repousse le problème, et `GOMEMLIMIT` doit suivre) ; (5) la taille de la file de l'exportateur (ne joue que si Tempo est lent ; une file trop grande aggrave l'OOM).
6. **RATE_LIMITED** : l'application ne voit rien (elle a déjà envoyé à l'agent, qui a accepté) ; la passerelle voit des erreurs d'envoi retentables, réessaie avec une attente croissante ; les données sont dans la **file** de l'exportateur de la passerelle (mémoire) pendant au plus `max_elapsed_time` (300 s ici) par lot, puis abandonnées (`otelcol_exporter_send_failed_spans`) ; si la file se remplit avant, les nouveaux lots sont refusés à l'entrée de la file (`enqueue_failed`).
7. **File infinie** : elle transforme une panne de Tempo en panne mémoire de la passerelle (OOM, perte de **tout** ce qui est en mémoire, y compris les traces en attente de décision) ; une file bornée perd les données les plus récentes de façon contrôlée et mesurée. Persistante (`file_storage`), la file vit sur disque : elle survit à un redémarrage et peut être bien plus grande sans coût mémoire, au prix d'un volume, d'écritures disque et de l'incompatibilité avec `wait_for_result`.
8. **30 000 spans** : `max_bytes_per_trace` (5 Mo par défaut) a sauté (`TRACE_TOO_LARGE`). Ne pas la relever par principe : une trace de 30 000 spans n'est lisible par personne et coûte cher à chaque recherche. Proposer à l'équipe une span par **lot** (avec des événements ou des liens vers des traces par élément), ou une trace par élément liée à la trace du lot (*span links*).
9. **Un an** : les traces contiennent des données techniques sur des parcours de soin (routes, durées, identifiants techniques) : les garder un an augmente l'exposition sans répondre à l'exigence. L'audit HDS demande la **traçabilité des accès** aux données de santé : c'est le journal d'audit (Loki, locataire `audit`, 365 jours, M22) et les journaux applicatifs d'accès qui y répondent, pas les traces. Réponse : 14 jours de traces, justification écrite dans l'ADR.
10. **Ce qu'un profil *on-CPU* ne montre pas** : l'attente d'entrée-sortie (base de données, Valkey, MédiDoc : visible dans la trace) ; l'étranglement CFS par une limite CPU (visible dans `container_cpu_cfs_throttled_periods_total`) ; l'attente d'un verrou ou d'une connexion du réservoir (`psycopg_pool`) : visible dans la trace (span longue sans enfant) et dans les métriques du réservoir ; aussi la file d'attente de la machine (CPU saturé par d'autres pods : `node_pressure`, PSI).
11. **Coûts** : une série de métrique coûte quelques octets par échantillon, quelle que soit la charge ; une ligne de journal et une span coûtent à chaque requête ; un profil coûte en continu mais peu. Pour « l'API est-elle lente depuis 10 h », la **métrique** (histogramme de latence) répond en une requête sur des données agrégées ; traces et journaux viennent ensuite, pour expliquer.
12. **Jeton fuité** : générer un nouveau jeton (Vault), l'ajouter au Secret à côté de l'ancien (`secrets-k8s.sh otel`), le donner à l'émetteur, vérifier qu'il l'utilise (journaux de la passerelle, ou trace de l'émetteur reçue), retirer l'ancien du Vault et relancer `secrets-k8s.sh`. L'ancien jeton reste accepté jusqu'à ce que le Secret mis à jour soit propagé au pod (période de synchronisation du kubelet, une à deux minutes) et relu par l'extension. Purger le ticket qui contenait le jeton, et le mentionner dans un court rapport d'incident de sécurité (Sophie).
13. **Arête qui disparaît** : côté instrumentation, (a) la propagation ne passe plus (propagateurs, relais qui retire `traceparent`) : la span serveur de MédiDoc n'a plus pour parent la span client de MédiAgenda ; (b) la span client n'existe plus ou n'a plus le bon type (`kind = client`) ou les attributs qui identifient le pair, ou l'échantillonneur de MédiDoc n'est pas `parentbased`. Côté Collector : (c) les deux côtés de l'arête arrivent sur des réplicas différents de la passerelle (pas d'équilibrage par `traceID`) et l'échantillonnage en queue garde l'un sans l'autre, ou le *metrics-generator* ne les voit pas dans la fenêtre `wait`.
