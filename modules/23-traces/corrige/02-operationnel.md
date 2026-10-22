# Module 23 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Mêmes conventions que le corrigé du palier 1 : les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice (`observabilite/` = `plateforme/observabilite`, `deploiement-mediagenda/` et `deploiement-medidoc/` = les dépôts de déploiement, `mediagenda-api/` et `medidoc/` = des **correctifs** `git apply` sur le code, `medisphere/` = la documentation). Les correctifs s'appliquent **dans l'ordre**, chacun sur l'état laissé par le précédent : pour `mediagenda/api`, M22-E06 (`request-id.patch`), M23-E04 (`traces.patch`), M23-E06 (`medidoc.patch`), M23-E08 (`correlation.patch`), puis M23-E14 (`profilage.patch`, palier 3) ; pour `medidoc/medidoc`, M23-E06 (`traces.patch`), M23-E08 (`correlation.patch`), puis M23-E14 (`profilage.patch`). Les dépendances s'ajoutent par `uv add` (Python) avant chaque correctif ; `go.mod` et `go.sum` sont dans les correctifs Go.

**Ce qui a été vérifié à la rédaction** :
- MédiDoc : correctifs E06 puis E08 appliqués sur une copie de `apps/medidoc` ; `go vet ./...` et `go test ./...` verts (Go 1.26, otel 1.47.0, otelhttp/otelaws/autoprop 0.72.0) ; exécuté contre un S3 simulé : spans serveur nommées d'après le motif de route, spans S3 `S3.PutObject` filles de la span serveur, sondes absentes ;
- MédiAgenda : correctifs E06 puis E08 appliqués à la suite de M22-E06 et M23-E04 ; `uv run pytest`, `ruff check`, `ruff format --check` verts ; **trace distribuée** relevée de bout en bout (MédiAgenda → MédiDoc → S3) dans un Tempo 3.1.1 local, `traceparent` vérifié par test ; `/metrics` en OpenMetrics avec exemplars `trace_id` sur les deux applications ;
- configurations des Collectors de E09 et E10 validées par `otelcol-contrib validate` 0.161.0 et exécutées : échantillonnage en queue mesuré (10 traces gardées sur 100 « normales », 2/2 en erreur, 2/2 lentes) ; masquage des NIR et des courriels constaté, identifiants hexadécimaux intacts, `url.query` supprimé, littéraux SQL remplacés, spans de sonde filtrées dans les deux conventions ;
- `config.alloy` : `alloy fmt` et `alloy validate` (1.21.1) ; `values.yaml` de kps rendu par `helm template` (option `--enable-feature=exemplar-storage` et `exemplarTraceIdDestinations` présents) ; manifestes : `kustomize build` et `kubeconform -strict` ;
- `ressources/E11-collector-lucas/otel-lucas.yaml` : les deux configurations démarrent avec `otelcol-contrib` 0.161 (adresses en `127.0.0.1`) et affichent les avertissements d'alias dépréciés ;
- le script de panne de E12 : SQL de la variante 1 exécuté sur PostgreSQL 16 (insertion à ≈ 400 ms, retrait propre) ; `shellcheck -x`, `bash -n` ; checks exécutés à vide sous `set -euo pipefail`.

**Points non testés en conditions réelles** : le déploiement dans `k8s-par1` (politiques Cilium entre espaces, droits du résolveur `k8s` de l'exportateur `loadbalancing`, webhook d'injection de l'opérateur sous Pod Security, image `autoinstrumentation-python` par le cache `ghcr`), l'API des exemplars de Thanos Query (le check retombe sur un message explicite si elle ne répond pas), le RGW de Ceph pour MédiDoc instrumenté, la variante 2 de E12 (`CLIENT PAUSE` testé sur Redis 7 local seulement). Les sorties montrées sont représentatives.

---

### M23-E06 — Instrumenter MédiDoc avec le SDK Go

**Solution**

1. **MédiDoc** : correctif [`medidoc/traces.patch`](fichiers/M23-E06/medidoc/traces.patch) (avec `go.mod` et `go.sum`) :
   ```
   admin@adm01:~/src/medidoc$ git switch -c traces-otel
   admin@adm01:~/src/medidoc$ git apply --index ~/DevOpsPrivateCloud/modules/23-traces/corrige/fichiers/M23-E06/medidoc/traces.patch
   admin@adm01:~/src/medidoc$ go mod verify && go vet ./... && go test ./...
   all modules verified
   ok  	git01.par1.medisphere.internal/medidoc/medidoc/internal/config	0.004s
   ok  	git01.par1.medisphere.internal/medidoc/medidoc/internal/serveur	0.021s
   ok  	git01.par1.medisphere.internal/medidoc/medidoc/internal/stockage	0.009s
   ok  	git01.par1.medisphere.internal/medidoc/medidoc/internal/telemetrie	0.012s
   ```
   - `internal/telemetrie/telemetrie.go` : `Demarrer(ctx, version)` installe `autoprop.NewTextMapPropagator()`, une ressource (`resource.WithFromEnv()`, `WithTelemetrySDK()`, `service.version`), l'exportateur `otlptracegrpc` **par lots** seulement si un point d'envoi est configuré, et laisse le SDK lire `OTEL_TRACES_SAMPLER` ; renvoie `Shutdown`. `HorsSondes` exclut `/healthz`, `/readyz`, `/metrics`.
   - `cmd/medidoc/main.go` : `Demarrer` **avant** `stockage.NouveauClient` ; arrêt différé borné à 5 s ; `otelhttp.NewHandler(srv.Handler(), "medidoc", otelhttp.WithFilter(telemetrie.HorsSondes))`.
   - `internal/stockage/client.go` : `otelaws.AppendMiddlewares(&cfg.APIOptions)` avant `s3.NewFromConfig`.
   - `internal/serveur/serveur.go` : `medidoc.document.id` et `medidoc.document.taille` sur la span serveur du dépôt, jamais le patient ni le nom du fichier.
   - Tests (`tracetest.SpanRecorder`) : span nommée `POST /documents`, `trace_id` et parent repris d'un `traceparent` entrant, sondes non tracées, aucun attribut `patient` ni nom de fichier.
2. **MédiAgenda** : correctif [`mediagenda-api/medidoc.patch`](fichiers/M23-E06/mediagenda-api/medidoc.patch) et dépendances ([`pyproject.toml.extrait`](fichiers/M23-E06/mediagenda-api/pyproject.toml.extrait)) :
   ```
   admin@adm01:~/src/mediagenda-api$ uv add "httpx>=0.28,<1" "opentelemetry-instrumentation-httpx>=0.66b1,<0.67"
   admin@adm01:~/src/mediagenda-api$ git apply --index …/M23-E06/mediagenda-api/medidoc.patch
   admin@adm01:~/src/mediagenda-api$ uv run pytest -q
   ```
   `config.py` (`MEDIAGENDA_MEDIDOC_URL`, vide = 503), `documents.py` (client `httpx.AsyncClient`, `Timeout(10.0, connect=2.0)`, `ErreurMediDoc` si la réponse n'est pas 201), `app.py` (route `POST /api/v1/rendez-vous/{rdv_id}/pieces-jointes`, 404 si le rendez-vous n'existe pas, 413 au-delà de 10 Mio, span `mediagenda.piece_jointe.deposer` en `ERROR` puis 502 si MédiDoc échoue), `telemetrie.py` (`HTTPXClientInstrumentor().instrument()` au démarrage, avant la création du client). Le test de propagation instrumente le client simulé (`instrument_client`) et compare le `trace_id` de l'en-tête `traceparent` reçu par le faux MédiDoc à celui de la span serveur de MédiAgenda.
3. **Livraison.** Dans `medidoc/deploiement` : [`components/telemetrie`](fichiers/M23-E06/deploiement-medidoc/components/telemetrie/kustomization.yaml) (même forme que celui de MédiAgenda, `OTEL_SERVICE_NAME=medidoc`), et dans chaque overlay l'étiquette `medisphere.internal/environnement`, le component et la politique d'entrée ([dev](fichiers/M23-E06/deploiement-medidoc/overlays/dev/kustomization.extrait.yaml), [recette](fichiers/M23-E06/deploiement-medidoc/overlays/recette/kustomization.extrait.yaml)). Dans `mediagenda/deploiement` : `MEDIAGENDA_MEDIDOC_URL` et la politique de sortie par overlay ([dev](fichiers/M23-E06/deploiement-mediagenda/overlays/dev/kustomization.extrait.yaml), [recette](fichiers/M23-E06/deploiement-mediagenda/overlays/recette/kustomization.extrait.yaml)). Les deux politiques visent le port **8080** (celui du conteneur) et le pod de l'**autre** espace par `k8s:io.kubernetes.pod.namespace` + `app.kubernetes.io/name` :
   ```
   admin@adm01:~/src/medidoc-deploiement$ kustomize build overlays/recette | yq 'select(.kind == "CiliumNetworkPolicy") | .metadata.name'
   …
   medidoc-entree-mediagenda
   ```
4. **Constat** (fichier factice, dev) :
   ```
   admin@adm01:~$ printf '%%PDF-1.4 essai\n' > /tmp/essai.pdf
   admin@adm01:~$ curl -s -X POST -H 'Content-Type: application/pdf' --data-binary @/tmp/essai.pdf \
     "http://localhost:8000/api/v1/rendez-vous/1/pieces-jointes?nom=essai.pdf"
   {"rdv_id":1,"document_id":"8c0f…","taille":16}
   ```
   Trace (relevé local, représentatif) :
   ```
   mediagenda-api  POST /api/v1/rendez-vous/{rdv_id}/pieces-jointes   SERVER    48 ms
   mediagenda-api  └─ SELECT                                          CLIENT     2 ms
   mediagenda-api  └─ mediagenda.piece_jointe.deposer                 INTERNAL  41 ms
   mediagenda-api     └─ POST                                         CLIENT    40 ms  server.address=medidoc.medidoc-dev.svc.cluster.local
   medidoc               └─ POST /documents                           SERVER    37 ms  medidoc.document.id=8c0f… medidoc.document.taille=16
   medidoc                  └─ S3.PutObject                           CLIENT    31 ms  rpc.system=aws-api rpc.service=S3 rpc.method=PutObject
   ```
   Deux services, six spans ; le parent de la span serveur de MédiDoc est la span **client** `POST` de MédiAgenda (son `span_id` est celui de l'en-tête `traceparent`) ; l'essentiel du temps est dans le RGW. Requête structurelle :
   ```
   { resource.service.name = "mediagenda-api" } >> { resource.service.name = "medidoc" && kind = server }
   ```
5. [`conventions-telemetrie.md`](fichiers/M23-E10/medisphere/docs/observabilite/traces/conventions-telemetrie.md) (version finale, après E10) : section MédiDoc, attributs `medidoc.*`.

**Explications**

La propagation tient en deux instrumentations qui ne se connaissent pas : le client `httpx` **injecte** le contexte courant dans les en-têtes sortants (propagateur global, W3C par défaut), `otelhttp` l'**extrait** des en-têtes entrants et en fait le parent de sa span serveur. Il suffit que les deux côtés aient le même propagateur (`OTEL_PROPAGATORS=tracecontext,baggage` dans les deux components) et que rien entre les deux ne retire l'en-tête. `otelhttp` enveloppe le `ServeMux` : la span est créée avant le routage, son nom (`POST /documents`) est fixé à partir de `r.Pattern` quand le mux l'a renseigné (Go 1.22+). `otelaws` ajoute un *middleware* à la pile du SDK AWS : une span par opération (`S3.PutObject`), reprenant le contexte de la requête passé à `PutObject(ctx, …)`. Une politique Cilium s'applique **après** la traduction du Service : la sortie de MédiAgenda vise le pod MédiDoc sur 8080, pas le Service sur 80.

**Alternatives**

- Exportateur OTLP **HTTP** en Go (`otlptracehttp`) : même résultat, sans gRPC.
- `autoexport` (contrib) choisit l'exportateur d'après `OTEL_TRACES_EXPORTER` : plus souple, une dépendance de plus.
- Nommer les spans soi-même (`otelhttp.WithSpanNameFormatter`) si l'application tourne sur un Go antérieur à 1.22 ou un routeur tiers.
- Appel de MédiDoc depuis un traitement asynchrone (file) : la trace se prolonge par un **lien** de span, pas par une relation parent-enfant.

**Pièges classiques**

- `Demarrer` après la création du client S3 : `otelaws` n'est jamais installé, aucune span S3.
- Oublier `Shutdown` : les spans des dernières secondes d'un pod arrêté sont perdues.
- Politique de sortie vers le port **80** du Service : refusée, la requête expire (502 côté MédiAgenda après 10 s, 2 s à la connexion).
- Une politique qui laisse dev parler à recette (`k8s:io.kubernetes.pod.namespace` oublié ou sélecteur trop large).
- Mettre le nom du fichier en attribut, ou laisser `?nom=` dans `url.full` : le cas exact du ticket de Sophie (E10).
- `HTTPXClientInstrumentor().instrument()` après la création du client : pas de span client, **et** pas de `traceparent` : deux traces séparées.
- Étiquette d'environnement oubliée dans un overlay de MédiDoc : `deployment.environment.name` vide, la trace de recette ne sort pas des requêtes filtrées par environnement.

**En production chez MédiSphère**

La production reçoit MédiDoc instrumenté avec le mini-projet, après la recette. Le *baggage* (pour aller plus loin) n'est propagé qu'avec une liste blanche de clés (`medisphere.canal`), documentée dans `conventions-telemetrie.md` : tout ce qui y entre voyage en clair dans chaque appel.

---

### M23-E07 — L'auto-instrumentation par l'opérateur, en comparaison

**Solution**

1. [`essais/instrumentation.yaml`](fichiers/M23-E07/essais/instrumentation.yaml) : `Instrumentation` `python-essai` (`exporter.endpoint: http://otel-agent-collector.traces.svc.cluster.local:4318`, propagateurs `tracecontext` et `baggage`, `parentbased_traceidratio` à `"1"`, `resourceAttributes`, image `registry.par1.medisphere.internal/ghcr/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.66b1`, `initContainerSecurityContext` compatible `restricted`, variables `OTEL_PYTHON_EXCLUDED_URLS`, `OTEL_SEMCONV_STABILITY_OPT_IN=http,database`, `OTEL_METRICS_EXPORTER=none`, `OTEL_LOGS_EXPORTER=none`).
2. [`essais/donnees-essai.yaml`](fichiers/M23-E07/essais/donnees-essai.yaml) (PostgreSQL et Valkey jetables) et [`essais/mediagenda-auto.yaml`](fichiers/M23-E07/essais/mediagenda-auto.yaml) (annotations **sur le gabarit du pod**) :
   ```
   admin@adm01:~$ kubectl -n wb-essais apply -f essais/
   admin@adm01:~$ kubectl -n wb-essais get pod -l app.kubernetes.io/name=mediagenda-auto -o yaml \
     | yq '.items[0].spec | (.initContainers[].name, .volumes[].name, (.containers[0].env[].name | select(test("^(OTEL|PYTHONPATH)"))))'
   opentelemetry-auto-instrumentation-python
   opentelemetry-auto-instrumentation-python
   PYTHONPATH
   OTEL_EXPORTER_OTLP_ENDPOINT
   OTEL_SERVICE_NAME
   …
   ```
   Le webhook a ajouté un conteneur d'initialisation qui copie le SDK et les instrumentations dans un `emptyDir`, monté dans `api`, et un `PYTHONPATH` qui charge `sitecustomize.py` avant l'application. Coût : quelques secondes de démarrage et la copie (dizaines de Mo).
3. Comparaison sur `POST /api/v1/rendez-vous` : la copie a la span serveur, l'`INSERT` et les `DEL`, **aucune** span métier (`mediagenda.rendez_vous.creer`, `mediagenda.cache.invalider`) ni attribut `mediagenda.*` ; les spans PostgreSQL et Valkey sont filles directes de la span serveur.
4. Mémoire : `kubectl top pod` ou la requête du M21 sur `container_memory_working_set_bytes{container="api"}` ; l'auto-instrumentation charge toutes les instrumentations de l'image, d'où quelques dizaines de Mio de plus.
5. Double instrumentation : voir le livrable. Retirer l'annotation recrée les pods sans injection.
6. Livrable : [`auto-instrumentation.md`](fichiers/M23-E07/medisphere/docs/observabilite/traces/auto-instrumentation.md). Nettoyage : `kubectl -n wb-essais delete -f essais/` et le Secret de la base jetable.

**Explications**

L'opérateur ne modifie rien après coup : il **mute le pod à sa création** (webhook). Le SDK démarre par `sitecustomize`, avant le code de l'application, avec les instrumentations de l'image de l'opérateur, configuré par variables d'environnement. Il ne connaît que les bibliothèques : le métier (le rendez-vous, le cache), c'est-à-dire ce qui explique une lenteur, n'y est pas. Le fournisseur global ne s'installe qu'une fois : le premier gagne (celui de `sitecustomize`), l'autre est refusé avec un avertissement, et l'instrumentation FastAPI peut s'appliquer deux fois.

**Alternatives**

- `opentelemetry-instrument` dans l'image (même principe, versions choisies et testées par l'équipe) : l'auto-instrumentation sans webhook.
- Pour Go : agent eBPF de l'opérateur (désactivé par défaut, conteneur privilégié) ou OBI/Beyla (palier 3) : aucune modification du binaire, mais des droits noyau.

**Pièges classiques**

- Annotation sur le Deployment au lieu du gabarit : rien n'est injecté, sans erreur.
- Point d'envoi en `:4317` avec l'image Python (OTLP HTTP) : spans perdues, erreurs de connexion dans les journaux du pod.
- `Instrumentation` dans un autre espace que le pod sans le préfixer (`autre-espace/nom`) : injection refusée (événement sur le ReplicaSet).
- Oublier `initContainerSecurityContext` : le conteneur injecté est refusé par Pod Security.
- Laisser l'essai en place : un webhook qui mute les pods et une base jetable oubliés dans `wb-essais`.

**En production chez MédiSphère**

Pas d'`Instrumentation` hors de `wb-essais` (le check y veille). La décision est reprise dans l'ADR-0230 (M23-E17).

---

### M23-E08 — Corrélation : exemplars, `trace_id` dans les journaux, liens Grafana

**Solution**

1. **MédiAgenda** : [`mediagenda-api/correlation.patch`](fichiers/M23-E08/mediagenda-api/correlation.patch). `journal.py` : le formateur JSON ajoute `trace_id` (`format(ctx.trace_id, "032x")`) et `span_id` (`"016x"`) si `get_current_span().get_span_context().is_valid` ; `app.py` : `observe(durée, exemplar={"trace_id": …})` seulement si la span est **échantillonnée** (`trace_flags.sampled`), `/metrics` répond par `choose_encoder(request.headers.get("accept"))` (OpenMetrics si demandé). Tests.
2. **MédiDoc** : [`medidoc/correlation.patch`](fichiers/M23-E08/medidoc/correlation.patch). `internal/telemetrie/journal.go` : un `slog.Handler` qui enveloppe le gestionnaire JSON et ajoute les deux identifiants dans `Handle(ctx, r)` ; les journaux des gestionnaires HTTP passent `r.Context()` (`InfoContext`…) ; `prometheus.ExemplarObserver` sur l'histogramme ; `promhttp.HandlerOpts{EnableOpenMetrics: true}`. Tests.
3. Livraison : MR, CI, promotions (dev puis recette) des deux applications.
4. **Alloy** : [`alloy/config.alloy`](fichiers/M23-E08/observabilite/alloy/config.alloy) : dans les deux `stage.match` (MédiAgenda, MédiDoc), `stage.json` extrait `trace_id` et `span_id`, `stage.structured_metadata` les range ; la liste d'étiquettes du M22 ne change pas. Contrôle dans Explore : `{service_name="mediagenda-api"} | trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"`.
5. **Grafana** : [`grafana/sources-loki.yaml`](fichiers/M23-E08/observabilite/grafana/sources-loki.yaml) (sur `loki-mediagenda` et `loki-medidoc` : `derivedFields` `matcherType: label`, `matcherRegex: trace_id`, `datasourceUid: tempo`, `url: $${__value.raw}`), [`grafana/sources-tempo.yaml`](fichiers/M23-E08/observabilite/grafana/sources-tempo.yaml) (`tracesToLogsV2` vers `loki-mediagenda`, filtre par `k8s.namespace.name` et `trace_id`), [`kps/values.yaml.extrait`](fichiers/M23-E08/observabilite/kps/values.yaml.extrait) (`prometheus.prometheusSpec.enableFeatures: [exemplar-storage]`, `exemplars.maxSize`, `grafana.sidecar.datasources.exemplarTraceIdDestinations: {datasourceUid: tempo, traceIdLabelName: trace_id}`).
   ```
   admin@adm01:~$ kubectl -n supervision get prometheus kps-prometheus -o jsonpath='{.spec.enableFeatures}'
   ["exemplar-storage"]
   admin@adm01:~$ kubectl -n supervision exec prometheus-kps-prometheus-0 -c prometheus -- \
     wget -qO- 'http://localhost:9090/api/v1/query_exemplars?query=mediagenda_http_request_duration_seconds_bucket' | jq -r '.data[0].exemplars[0].labels.trace_id'
   4bf92f3577b34da6a3ce929d0e0e4736
   ```
6. Les trois chemins fonctionnent ; ce qui ne marche pas toujours : un exemplar qui désigne une trace écartée par l'échantillonnage en queue (E09), le lien Tempo → Loki d'une span de MédiDoc qui ouvre le locataire `mediagenda`, une ligne de journal hors requête (démarrage) sans `trace_id`.
7. Livrable : [`correlation.md`](fichiers/M23-E08/medisphere/docs/observabilite/traces/correlation.md).

**Explications**

Trois mécanismes, un même identifiant. Journal → trace : le `trace_id` est une **métadonnée structurée** de Loki (indexée à part, cardinalité illimitée sans multiplier les flux), le champ dérivé de type « label » en fait un lien interne vers Tempo. Trace → journaux : Grafana construit une requête LogQL à partir de la span (espace, identifiant de trace). Métrique → trace : l'exemplar est stocké par Prometheus à côté de l'observation, transmis seulement dans le format **OpenMetrics** (le format texte classique n'a pas de place pour lui), et Grafana l'affiche en point cliquable. `$$` dans un fichier provisionné échappe l'interpolation des variables d'environnement de Grafana.

**Alternatives**

- `trace_id` en **étiquette** Loki : interdit (un flux par requête, l'ingesteur s'effondre).
- Exemplars par le Collector (connecteur `spanmetrics`) ou par le *metrics-generator* de Tempo (M23-E13) au lieu des applications.
- Une source Loki multi-locataire pour le lien depuis Tempo (à décider avec l'équipe du M22).

**Pièges classiques**

- `trace_id` formaté en décimal ou sans zéros de tête : le lien ouvre une trace introuvable.
- Exemplar posé sur une trace non échantillonnée : lien mort assuré.
- `/metrics` en texte seulement : `exemplar-storage` activé, aucun exemplar stocké, aucune erreur.
- Un `slog.Info(…)` sans contexte dans un gestionnaire Go : la ligne n'a pas de `trace_id`.
- Interroger les exemplars par Thanos Query et conclure à leur absence : demander d'abord au pod Prometheus.
- Modifier la source Prometheus dans l'interface : écrasée au prochain redémarrage de Grafana (sources provisionnées).

**En production chez MédiSphère**

Les trois liens sont le premier réflexe du runbook RB-234 « l'API est lente » (pour aller plus loin de M23-E12). Les exemplars ne vivent que dans le WAL de Prometheus (quelques heures) : pour un incident de la veille, partir des journaux.

---

### M23-E09 — Échantillonnage en tête et en queue

**Solution**

1. Réflexion (dans le livrable) : ratio en tête **1.0** (la règle de Karim exige toutes les erreurs et toutes les traces lentes, que la tête ne peut pas connaître) ; avec deux réplicas derrière un Service ordinaire, les spans d'une trace se répartissent selon les connexions des agents : chaque réplica décide sur un morceau, on garde des traces amputées.
2. **Agents** : [`otel/otel-agent.yaml`](fichiers/M23-E09/observabilite/otel/otel-agent.yaml) (exportateur `loadbalancing/passerelle`, `routing_key: traceID`, `protocol.otlp` avec file d'attente et reprises, résolveur `k8s` sur `otel-passerelle-collector-headless.traces`, port 4317) et [`otel/rbac-agent.yaml`](fichiers/M23-E09/observabilite/otel/rbac-agent.yaml) (Role et RoleBinding `otel-agent-loadbalancing` dans `traces` : `get`, `list`, `watch` sur `discovery.k8s.io/endpointslices`).
3. **Passerelle** : [`otel/otel-passerelle.yaml`](fichiers/M23-E09/observabilite/otel/otel-passerelle.yaml) : `replicas: 2`, `podDisruptionBudget` (`maxUnavailable: 1`), `topologySpreadConstraints` par nœud, mémoire 512 Mi demandés / 1 Gi limite, pipeline `[memory_limiter, tail_sampling, batch]`, `tail_sampling` : `decision_wait: 10s`, `num_traces: 20000`, politiques `erreurs` (`status_code: [ERROR]`), `lentes` (`latency.threshold_ms: 500`), `reste-10-pourcent` (`probabilistic.sampling_percentage: 10`).
4. **Applications** : components [`telemetrie` de MédiAgenda](fichiers/M23-E09/deploiement-mediagenda/components/telemetrie/kustomization.yaml) et [de MédiDoc](fichiers/M23-E09/deploiement-medidoc/components/telemetrie/kustomization.yaml) : `OTEL_TRACES_SAMPLER=parentbased_traceidratio`, `OTEL_TRACES_SAMPLER_ARG="1.0"`.
5. **Mesure** :
   ```
   sum by (sampled) (increase(otelcol_processor_tail_sampling_global_count_traces_sampled[10m]))
   sum(otelcol_processor_tail_sampling_sampling_trace_dropped_too_early)
   max by (pod) (otelcol_loadbalancer_num_backends)
   ```
   Sur 100 traces normales, ≈ 10 gardées ; toutes les traces en erreur (`{ status = error }`) et lentes (`{ trace:duration > 500ms }`) sont là ; `dropped_too_early` à 0 ; chaque agent voit 2 réplicas. À 0,25 en tête : 75 % des erreurs disparaissent **avant** la passerelle ; les traces gardées restent entières (MédiDoc suit la décision de MédiAgenda grâce à `parentbased`). Remettre 1.0.
6. Livrable : [`echantillonnage.md`](fichiers/M23-E09/medisphere/docs/observabilite/traces/echantillonnage.md).

**Explications**

L'échantillonnage en queue ne peut décider qu'après avoir vu la trace : il **attend** (`decision_wait`) en gardant les spans en mémoire, d'où `num_traces`, la mémoire de la passerelle et `memory_limiter` en tête. L'exportateur `loadbalancing` hache le `trace_id` (anneau de hachage cohérent) : tous les agents envoient les spans d'une trace au même réplica, quel que soit le nœud d'origine. Il lui faut l'adresse de **chaque** pod (le Service sans tête, pas l'adresse virtuelle) ; le résolveur `k8s` les lit dans les EndpointSlices et suit les changements en direct. Une politique `OR` : la trace est gardée dès qu'une politique la retient.

**Alternatives**

- Résolveur `dns` : aucun droit, réactivité moindre (interrogation périodique).
- Échantillonnage en tête seul, à 10 % : simple, mais 90 % des erreurs perdues : refusé par la règle.
- Échantillonnage en queue dans Tempo ou dans un produit tiers : non disponible dans notre architecture, et le volume traverserait le réseau pour rien.
- Échantillonnage **cohérent** (`tracestate ot=th:…`, pour aller plus loin) : permet d'extrapoler des comptes justes.

**Pièges classiques**

- Résolveur `k8s` sans droits : liste vide, « couldn't find the exporter for the endpoint "" », toutes les spans perdues.
- Viser `otel-passerelle-collector` (adresse virtuelle) dans le résolveur : un seul « réplica » vu, tout repart au hasard derrière.
- `tail_sampling` avant `memory_limiter`, ou `batch` avant `tail_sampling` (le lot mélange des traces, sans gravité mais inutile).
- `decision_wait` plus court que les traces les plus longues : traces lentes décidées avant leur fin, donc classées « normales ».
- Ratio en tête sans `parentbased` : MédiDoc tire sa propre décision et la trace se troue.
- Conclure à une baisse de trafic en comptant les traces dans Tempo.

**En production chez MédiSphère**

Le même réglage vaut pour la production, avec une surveillance de `dropped_too_early` et de `otelcol_processor_refused_spans` (alerte, M21). Les taux et SLO restent calculés sur les métriques des applications, jamais sur les traces.

---

### M23-E10 — Les pipelines du Collector : processeurs et données sensibles

**Solution** (une solution possible ; d'autres conceptions sont justes si elles tiennent toutes les garanties)

**Où** : dans l'**agent**, premier Collector traversé par les spans d'un pod : la donnée ne quitte pas le nœud, et la passerelle (échantillonnage en queue) reçoit des spans déjà propres. Le filet pour les spans reçues par 10.10.41.63 (sans agent) est l'objet du « pour aller plus loin » (M23-E16).

**Quoi**, dans [`otel/otel-agent.yaml`](fichiers/M23-E10/observabilite/otel/otel-agent.yaml), dans cet ordre :

| Processeur | Rôle |
|---|---|
| `memory_limiter` | toujours en premier |
| `filter/sondes` | jette les spans dont `url.path` (stable) **ou** `http.target` (ancienne convention) est une sonde ou `/metrics` ; avant l'enrichissement : pas de travail pour rien |
| `k8sattributes`, `resourcedetection`, `resource/cluster` | origine (espace, pod, uid, Deployment, nœud, cluster, équipe) ; liste fermée, pas d'annotations ni d'étiquettes de pod |
| `transform/masquage` (OTTL) | supprime `url.query`, coupe `?…` de `url.full` et `http.target`, remplace les littéraux `'…'` de `db.query.text` et `db.statement` par `'?'`, supprime `http.request.header.*` et `http.response.header.*` |
| `redaction/donnees-sante` | `allow_all_keys: true`, `blocked_values` : NIR et courriel (motifs bornés par `\b`), `summary: info` (attribut `redaction.masked.count`) |
| `batch` | toujours en dernier |

**Preuve par des données factices** (envoyées à l'agent par un port-forward, ou à un Collector local avec la même configuration) :
```
admin@adm01:~$ kubectl -n traces port-forward ds/otel-agent-collector 14318:4318 &
admin@adm01:~$ cat > /tmp/span-factice.json <<'EOF'
{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"essai-masquage"}}]},
 "scopeSpans":[{"spans":[{"traceId":"5b8efff798038103d269b633813fc60c","spanId":"eee19b7ec3c1b174","name":"GET /essai","kind":2,
  "startTimeUnixNano":"1767225600000000000","endTimeUnixNano":"1767225600100000000",
  "attributes":[{"key":"url.full","value":{"stringValue":"http://x/essai?nom=dupont.pdf"}},
   {"key":"url.query","value":{"stringValue":"nom=dupont.pdf"}},
   {"key":"db.query.text","value":{"stringValue":"SELECT * FROM p WHERE nom = 'Dupont'"}},
   {"key":"essai.libre","value":{"stringValue":"contact jeanne.dupont@example.org nir 2840575123456 78"}},
   {"key":"http.request.header.authorization","value":{"arrayValue":{"values":[{"stringValue":"Bearer x"}]}}}]}]}]}]}
EOF
admin@adm01:~$ curl -s -H 'Content-Type: application/json' --data @/tmp/span-factice.json http://localhost:14318/v1/traces
{"partialSuccess":{}}
```
Avec l'agent ainsi configuré, la span arrive dans Tempo avec `url.full=http://x/essai`, sans `url.query`, `db.query.text=SELECT * FROM p WHERE nom = '?'`, `essai.libre=contact **** nir **** 78` (la clé du NIR, séparée par une espace, reste : les 13 chiffres suffisent à masquer l'identifiant, mais un NIR écrit avec des espaces partout passerait : limite à documenter), sans en-tête, `redaction.masked.count=2`. Une span `GET /sante` envoyée de la même façon n'arrive pas. Le port-forward passe par l'agent : `k8sattributes` n'enrichit pas ces spans (connexion depuis l'API, pas depuis un pod), ce qui est attendu.

**Preuve sur les données réelles** (dernière heure, avec trafic), chacune doit répondre **vide** :
```
{ span.url.path =~ "/(sante|pret|metrics|healthz|readyz)" || span.http.target =~ "/(sante|pret|metrics|healthz|readyz).*" }
{ span.url.query != nil || span.url.full =~ ".*[?].*" || span.http.target =~ ".*[?].*" }
{ span.db.query.text =~ ".*'[^?'][^']*'.*" || span.db.statement =~ ".*'[^?'][^']*'.*" }
{ span."http.request.header.authorization" != nil || span."http.response.header.set-cookie" != nil }
{ span.mediagenda.patient != nil || span.patient != nil }
```
Et une requête de contrôle qui, elle, doit trouver : `{ span.redaction.masked.count > 0 }` (vide en temps normal ; non vide = un émetteur fuit, à corriger dans son code). [`conventions-telemetrie.md`](fichiers/M23-E10/medisphere/docs/observabilite/traces/conventions-telemetrie.md) décrit le masquage, ses limites et ces requêtes.

**Explications**

Deux familles de défenses : par **règles** (on sait quel attribut porte quoi : `url.query`, `db.query.text`, en-têtes) et par **motifs** (on ne sait pas où la donnée apparaîtra : un message d'exception, un attribut inventé par une équipe). Les règles sont exactes et peu coûteuses ; les motifs attrapent l'imprévu, avec des faux positifs et des faux négatifs. L'ordre compte : filtrer d'abord (moins de travail), enrichir ensuite, masquer après l'enrichissement (une étiquette de pod pourrait porter une donnée), regrouper en dernier. Les règles doivent couvrir **les deux** conventions sémantiques : les émetteurs anciens (auto-instrumentation, outils tiers) écrivent `http.target` et `db.statement`.

**Alternatives**

- Processeur `attributes` (actions `delete`, `hash`) au lieu de `transform` pour les suppressions simples ; `transform` reste nécessaire pour réécrire une partie de valeur.
- `redaction` en liste blanche (`allowed_keys`) : la défense la plus forte (tout attribut non prévu est supprimé), mais il faut tenir la liste de chaque instrumentation à jour ; à envisager pour la production.
- Masquer dans la passerelle : un seul endroit, mais la donnée a déjà traversé le réseau.
- Hacher au lieu de supprimer (`SHA256`) pour garder la possibilité de regrouper : un NIR haché reste une donnée personnelle (pseudonymisation, pas anonymisation).

**Pièges classiques**

- Filtrer seulement `url.path` : les spans de l'auto-instrumentation sans conventions stables passent.
- `replace_pattern` sur un attribut absent avec `error_mode: propagate` : toutes les spans rejetées.
- Un motif sans limite de mot : des identifiants hexadécimaux (`trace_id` recopiés en attributs) masqués à tort ; ou un motif trop strict qui laisse passer le NIR avec espaces.
- Croire le filet suffisant : il ne voit ni les noms de span, ni les événements construits avec une variable dans tous les cas, ni le *baggage* qui circule entre services. La correction reste dans le code.
- Retirer `k8sattributes` de son rang : enrichir après `batch` casse l'association par connexion.

**En production chez MédiSphère**

Le filet est imposé à toute entrée de traces (agents, puis 10.10.41.63 en M23-E16) ; un masquage constaté (`redaction.masked.count`) ouvre un ticket SEC chez l'équipe émettrice. Sophie relit les règles à chaque nouvelle instrumentation.

---

### M23-E11 — Revue : la configuration du Collector du stagiaire

**Solution**

La revue de référence : [`revue-collector-lucas.md`](fichiers/M23-E11/medisphere/docs/observabilite/traces/revue-collector-lucas.md), 17 constats. Les six points exigés :

| Thème | Constat | Gravité |
|---|---|---|
| Mémoire | pas de `memory_limiter` dans l'agent, `batch` avant le limiteur dans la passerelle, `limit_mib: 4000` sans limite de conteneur | bloquant / majeur |
| Échantillonnage | `tail_sampling` sur 2 réplicas derrière un Service ordinaire, `probabilistic_sampler` en amont | majeur |
| Noms | `otlp` / `otlphttp` : alias dépréciés (avertissement au démarrage) | mineur |
| `debug` | `verbosity: detailed` en production : les spans, attributs compris, dans les journaux puis dans Loki | bloquant (données) |
| Tiers et chiffrement | `otlphttp/infoger` en `http://` vers InfoGér : données hors de MédiSphère, en clair | bloquant (HDS, RGPD) |
| Droits | `k8sattributes` sans compte de service ni RBAC ; toutes les annotations recopiées | majeur |

Décision : **MR refusée en l'état**, reprise à partir des CR de référence ([E09](fichiers/M23-E09/observabilite/otel/otel-passerelle.yaml), [E10](fichiers/M23-E10/observabilite/otel/otel-agent.yaml)). Ce que la MR fait bien : l'architecture agent + passerelle, une politique « erreurs », le récepteur HTTP.

Les deux défauts que le Collector signale lui-même (Indice 2), relevés avec la configuration de la passerelle (adresses en `127.0.0.1`) :
```
admin@adm01:~$ otelcol-contrib --config passerelle-lucas-local.yaml 2>&1 | grep -E 'warn'
… warn  builders/builders.go:40  "otlphttp" alias is deprecated; use "otlp_http" instead  … "otelcol.component.id": "otlphttp/infoger" …
… warn  builders/builders.go:40  "otlp" alias is deprecated; use "otlp_grpc" instead  … "otelcol.component.id": "otlp/tempo" …
```
Le premier désigne justement l'exportateur vers InfoGér : en remontant de l'avertissement à la configuration, on trouve le défaut le plus grave. Rien ne signale l'exportateur `debug` détaillé, l'absence de `memory_limiter` ou le Service exposé : c'est le travail de la revue.

**Explications**

Une configuration de Collector **valide** n'est pas une configuration **sûre** : `otelcol validate` vérifie la syntaxe et les types, pas l'ordre des processeurs, la répartition entre réplicas, la destination des données ni l'exposition réseau. La revue se fait avec trois questions (charge, attaquant, sortie) et la liste des invariants de la plateforme (images de Harbor, `memory_limiter` en tête, pas de tiers, pas de `debug` détaillé).

**Alternatives**

Une partie de ces règles peut être automatisée : politique Kyverno ou VAP sur les CR `OpenTelemetryCollector` (image, présence de `memory_limiter`, interdiction de `debug` détaillé), test en CI qui extrait la configuration et la passe à `otelcol-contrib validate`.

**Pièges classiques**

- S'arrêter aux défauts syntaxiques ou cosmétiques (noms dépréciés) et rater l'envoi à un tiers.
- Proposer « ajouter TLS » vers InfoGér : le problème n'est pas le chiffrement seul, c'est la sortie des données (décision de Sophie, ADR).
- Appliquer la proposition « pour voir » : interdit par le ticket (et le check le vérifie).

**En production chez MédiSphère**

Toute MR sur `otel/` passe par la revue de l'équipe plateforme et un contrôle de CI ; un envoi hors de MédiSphère est une décision de sécurité, pas une MR technique.

---

### M23-E12 — Trouver où passe le temps

**Solution**

La panne a deux variantes (tirées au sort par `lab/bin/break 23 12`). Démarche commune, puis ce qu'on trouve.

1. **Métriques** (M21) : quelles routes ?
   ```
   histogram_quantile(0.95, sum by (le, route, methode) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette"}[5m])))
   ```
2. **Traces** : quelles spans ?
   ```
   { resource.deployment.environment.name = "recette" && kind = server && duration > 300ms }
   { resource.deployment.environment.name = "recette" && kind = client && duration > 200ms } | select(span.db.system.name, span.db.query.text)
   ```
3. **Composant** : pourquoi ?

**Variante 1 — PostgreSQL.** Seuls les `POST` et `DELETE` de rendez-vous sont lents (≈ 400 ms de plus) ; dans chaque trace, la span `INSERT` (ou `DELETE`) occupe le temps ; les `SELECT` du même pod sont rapides (ni réseau ni charge). Sur le primaire, pendant le trafic :
```
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda \
  -c "SELECT pid, wait_event_type, wait_event, left(query, 60) FROM pg_stat_activity WHERE datname = 'mediagenda' AND state = 'active'"
  pid  | wait_event_type | wait_event |                     left
-------+-----------------+------------+------------------------------------------------------------
 41237 | Timeout         | PgSleep    | INSERT INTO rendez_vous (patient, praticien, debut, duree_m
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -c '\d rendez_vous'
…
Triggers:
    rendez_vous_journal BEFORE INSERT OR DELETE ON rendez_vous FOR EACH ROW EXECUTE FUNCTION journal_modifications()
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -c '\sf journal_modifications'
```
La fonction attend 400 ms (`pg_sleep(0.4)`) ; elle n'est ni dans les migrations ni dans le dépôt. Correction (accord de Julien) :
```
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda \
  -c 'DROP TRIGGER rendez_vous_journal ON rendez_vous' -c 'DROP FUNCTION journal_modifications()'
```

**Variante 2 — Valkey.** Les spans lentes sont des commandes Valkey (`GET`, `SET`, `DEL`), par à-coups jusqu'à 300 ms, sur toutes les routes qui touchent le cache ; PostgreSQL est rapide ; Valkey n'est ni saturé (CPU) ni en échec. Ce que Valkey a reçu :
```
admin@adm01:~$ kubectl -n mediagenda-recette exec sts/valkey -- valkey-cli INFO commandstats | grep -E 'cmdstat_client\|pause'
cmdstat_client|pause:calls=412,usec=…
```
Le compteur augmente d'environ un par seconde : quelqu'un suspend Valkey (`CLIENT PAUSE 300 ALL`). Qui ? Le journal d'audit de l'API (locataire `audit`, M22-E07 ; dans Grafana, organisation « Sécurité » depuis M22-E16) :
```
{job="kubernetes-audit"} |= "mediagenda-recette" |= "exec" |= "valkey"
```
montre des `create pods/exec` répétés, avec l'identité du kubeconfig d'administration (`user.username`) : un processus lancé depuis `adm01`. On retrouve la boucle (`ps -ef | grep -F 'CLIENT PAUSE'` sur `adm01`), on l'arrête, puis `valkey-cli CLIENT UNPAUSE`.

4. **Retour à la normale** : mêmes requêtes avec du trafic (`trafic.sh` sur un port-forward de `svc/mediagenda` en recette) : aucune span PostgreSQL > 300 ms, aucune span Valkey > 200 ms, aucune requête serveur > 300 ms.
5. **Journal** : exemple complet (variante 1, avec un paragraphe pour la variante 2) : [`2026-11-04-INC-5012-recette-lente.md`](fichiers/M23-E12/medisphere/docs/kubernetes/journal/2026-11-04-INC-5012-recette-lente.md).

Le script de panne est [`pannes/break-E12.sh`](pannes/break-E12.sh) ; il ne supprime aucune donnée, le déclencheur et la boucle sont marqués `wb:M23-E12`. Clôture : `lab/bin/break 23 12 --annuler` après la correction (il ne défait rien de ta réparation) ; s'il trouve la lenteur encore active, il la retire et laisse un témoin d'abandon que le check signale.

**Explications**

Les métriques disent **quoi** (quelle route, depuis quand), les traces disent **où** (quelle span, dans quel composant), les outils du composant disent **pourquoi** (`pg_stat_activity` : la session n'attend pas un verrou mais un sommeil ; `INFO commandstats` : une commande inhabituelle). Sans traces, la variante 1 ressemble à « la base est lente » et la variante 2 à « le réseau est lent » ; avec elles, on voit en quelques minutes **quelle** opération, et qu'une seule. Une span client ne mesure que le temps vu par l'application : connexion, attente dans le serveur, réponse ; elle ne distingue pas un serveur lent d'un serveur suspendu, d'où l'étape 3.

**Alternatives**

- `pg_stat_statements` (temps moyen par requête normalisée) pour la variante 1 ; `auto_explain` pour voir le plan et le temps des déclencheurs (`log_triggers`).
- `valkey-cli --latency` et `LATENCY DOCTOR` pour la variante 2 ; `CLIENT LIST` pour voir les clients bloqués.
- Le profilage (paliers 3-4) montrerait l'application **en attente** (I/O) et non en calcul : utile pour écarter l'hypothèse « code lent ».

**Pièges classiques**

- Commencer par redémarrer les pods ou PostgreSQL : la lenteur revient (le déclencheur est dans la base ; la boucle est sur `adm01`).
- Conclure « PostgreSQL est lent » sans regarder **quelles** requêtes : les `SELECT` sont rapides.
- Supprimer la table ou restaurer une sauvegarde : la panne ne touche aucune donnée, la correction est un `DROP TRIGGER`.
- Chercher dans les traces la cause de la variante 2 : elles montrent l'effet (Valkey lent), pas l'auteur ; c'est l'audit qui le donne.
- Utiliser `--annuler` pour se débarrasser de la lenteur : le check le détecte (témoin `M23-E12.abandon`) ; la lenteur doit être corrigée par toi, `--annuler` ne sert qu'à clore.
- Oublier le trafic après la correction : aucune trace récente, le check ne peut rien conclure.

**En production chez MédiSphère**

Les deux causes ont leur prévention : schéma comparé aux migrations en CI et droits DDL retirés au compte applicatif (M16) ; `exec` sur les pods de données réservé au bris de glace (RBAC, M24) et alerte sur la latence des commandes Valkey. La démarche (métriques → traces → composant) devient le runbook RB-234 « l'API est lente » (pour aller plus loin de M23-E12).
