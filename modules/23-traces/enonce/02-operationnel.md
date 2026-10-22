# Module 23 — Traces et profilage : palier 2 — Opérationnel

Une seule application tracée ne montre pas l'essentiel : la requête qui traverse plusieurs services. Ce palier instrumente MédiDoc en Go et lui fait recevoir un vrai appel de MédiAgenda ; compare ce que l'instrumentation dans le code apporte par rapport à l'auto-instrumentation de l'opérateur ; relie les traces aux journaux et aux métriques ; réduit le volume sans perdre les traces utiles ; retire des spans ce qui ne doit pas y être ; relit la configuration du stagiaire ; et finit par un vrai diagnostic de lenteur.

Prérequis : palier 1 (`lab/bin/check 23 04` et `lab/bin/check 23 05` verts).

---

### M23-E06 — Instrumenter MédiDoc avec le SDK Go  `LAB` `★★★`

> **Ticket DEV-2406** — *De : Julien Petit* — *Copie : Karim Benali*
> Les testeurs veulent joindre une ordonnance à un rendez-vous. MédiDoc sait ranger des documents : MédiAgenda lui passera le fichier, c'est tout. L'équipe MédiDoc instrumente son service en Go (HTTP et appels S3), et je veux **une seule trace** qui traverse les deux : de la requête du testeur à l'écriture dans le RGW. Un environnement ne parle qu'à son homologue (dev ↔ dev, recette ↔ recette).

**Objectifs pédagogiques**
- Initialiser le SDK OpenTelemetry Go (ressource, exportateur OTLP gRPC, propagateurs, arrêt propre).
- Instrumenter `net/http` (`otelhttp`) et le SDK AWS (`otelaws`) ; nommer les spans d'après les motifs de route.
- Instrumenter un client HTTP Python (`httpx`) et vérifier la **propagation** W3C de bout en bout.
- Ouvrir un flux applicatif entre deux espaces, dans les deux sens, au plus juste.

**Prérequis** : M23-E04 ; M19-E33 et M20-E33 (`medidoc/deploiement`, overlays dev et recette) ; M16-E46 (MédiDoc sur le RGW).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Modules Go | `go.opentelemetry.io/otel` et `…/sdk` **v1.47.0**, `…/exporters/otlp/otlptrace/otlptracegrpc` v1.47.0, `go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp`, `…/github.com/aws/aws-sdk-go-v2/otelaws`, `…/propagators/autoprop` **v0.72.0** |
| Variables (component `components/telemetrie` de `medidoc/deploiement`) | mêmes que MédiAgenda, avec `OTEL_SERVICE_NAME=medidoc` ; environnement lu sur l'étiquette `medisphere.internal/environnement`, à poser dans les overlays de MédiDoc |
| Nouvelle route de MédiAgenda | `POST /api/v1/rendez-vous/{rdv_id}/pieces-jointes?nom=<fichier>` : corps = le document (type dans `Content-Type`) ; MédiAgenda vérifie que le rendez-vous existe, puis appelle `POST /documents` de MédiDoc (champ `patient` = `rdv-<id>`, champ `fichier`) ; répond 201 `{"rdv_id", "document_id", "taille"}`, 404, 413 (10 Mio), 502 si MédiDoc échoue, 503 si MédiDoc n'est pas configuré |
| Configuration de MédiAgenda | `MEDIAGENDA_MEDIDOC_URL` (facultative) : `http://medidoc.medidoc-dev.svc.cluster.local` en dev, `…medidoc-recette…` en recette |
| Paquets Python ajoutés | `httpx` (dépendance de production), `opentelemetry-instrumentation-httpx` 0.66b1 |
| Réseau | espaces en refus par défaut ; MédiDoc écoute sur 8080 (Service `medidoc` port 80) |

**Travail demandé**

1. **MédiDoc, le SDK.** Un paquet `internal/telemetrie` : démarrage (propagateurs d'après `OTEL_PROPAGATORS`, ressource d'après l'environnement + `service.version`, exportateur OTLP gRPC par lots si un point d'envoi est configuré, échantillonneur d'après l'environnement) et arrêt (dernières spans envoyées, délai borné). Appelé dans `main.go` **avant** le client S3.
2. **MédiDoc, l'instrumentation.** Le gestionnaire HTTP enveloppé par `otelhttp` (sondes et `/metrics` exclues) ; le client S3 instrumenté par `otelaws` ; deux attributs métier sur la span serveur du dépôt (`medidoc.document.id`, `medidoc.document.taille`) — jamais le patient ni le nom du fichier. Tests : nom de span = motif de route, contexte W3C repris, aucune donnée de santé ; `go vet`, `go test` verts.
3. **MédiAgenda, l'appel.** Le client MédiDoc (`httpx` asynchrone, délais courts), la route de pièces jointes, une span métier `mediagenda.piece_jointe.deposer` (statut `ERROR` si MédiDoc échoue), l'instrumentation `httpx` activée au démarrage. Tests (MédiDoc simulé), dont un qui prouve que l'en-tête `traceparent` part bien vers MédiDoc avec le `trace_id` de la requête entrante.
4. **Livraison.** Les deux MR de code, les pipelines, les promotions. Dans `medidoc/deploiement` : component `telemetrie`, étiquette d'environnement dans les overlays. Les flux : entrée de MédiDoc depuis l'API MédiAgenda de **son** environnement, sortie de MédiAgenda vers MédiDoc de **son** environnement (politiques dans les dépôts de déploiement) ; `MEDIAGENDA_MEDIDOC_URL` par overlay.
5. **Constate.** Dépose une pièce jointe (fichier factice) en dev, puis en recette ; ouvre la trace : combien de services, combien de spans, quel parent pour la span serveur de MédiDoc, combien de temps dans le RGW ? Trouve-la par une requête TraceQL structurelle qui exige les deux services.
6. **Complète** `conventions-telemetrie.md` (MédiDoc, attributs `medidoc.*`).

**Critères de réussite**
- [ ] `medidoc/medidoc` dépend d'otel 1.47, `otelhttp`, `otelaws`, `autoprop` ; `main.go` enveloppe le gestionnaire HTTP ; `mediagenda/api` dépend de `httpx` et de son instrumentation.
- [ ] `medidoc-dev` : `OTEL_SERVICE_NAME=medidoc` ; `mediagenda-dev` : `MEDIAGENDA_MEDIDOC_URL` vers MédiDoc de dev.
- [ ] Tempo a des traces de `medidoc` avec des spans S3 sous la span serveur.
- [ ] Au moins une trace contient une span de `mediagenda-api` **et**, sous elle, la span serveur de `medidoc`.
- [ ] Aucune sonde de MédiDoc n'est tracée.

**Vérification** : `lab/bin/check 23 06`

<details><summary>Indice 1</summary>

`resource.New(ctx, resource.WithFromEnv(), resource.WithTelemetrySDK(), resource.WithAttributes(…))` lit `OTEL_SERVICE_NAME` et `OTEL_RESOURCE_ATTRIBUTES` ; `sdktrace.NewTracerProvider` lit `OTEL_TRACES_SAMPLER` ; `otlptracegrpc.New(ctx)` lit `OTEL_EXPORTER_OTLP_ENDPOINT`. `autoprop.NewTextMapPropagator()` honore `OTEL_PROPAGATORS` (défaut : `tracecontext,baggage`).
</details>

<details><summary>Indice 2</summary>

`otelhttp` enveloppe le **ServeMux** entier : la span est créée avant le routage, et renommée après, quand `r.Pattern` est connu (Go 1.22+). `otelaws.AppendMiddlewares(&cfg.APIOptions)` s'appelle sur la configuration AWS avant `s3.NewFromConfig`.
</details>

<details><summary>Indice 3</summary>

En Python, `HTTPXClientInstrumentor().instrument()` instrumente les **transports** HTTP de `httpx` : il doit être appelé avant la création du client. Dans les tests, le transport simulé (`httpx.MockTransport`) n'en est pas un : instrumente ce client-là (`instrument_client`). Côté réseau, une politique Cilium vise le pod **après** la traduction du Service : le port est celui du conteneur (8080).
</details>

**Pour aller plus loin** (facultatif) : fais propager à MédiDoc une entrée de *baggage* (`medisphere.canal=web`) et lis-la dans une span : utile, et pourquoi faut-il une liste blanche de clés ?

---

### M23-E07 — L'auto-instrumentation par l'opérateur, en comparaison  `LAB` `★★`

> **Ticket PLAT-2407** — *De : Claire Morel*
> Un fournisseur m'a dit qu'avec l'opérateur, « on annote le pod et on a les traces, sans toucher au code ». Si c'est vrai, pourquoi avez-vous modifié MédiAgenda ? Faites l'essai, sur une copie, dans `wb-essais` seulement, et écrivez-moi la comparaison et la décision. Et dites-moi ce qu'il en est pour MédiDoc, en Go.

**Objectifs pédagogiques**
- Mettre en œuvre une ressource `Instrumentation` et l'injection par annotation (webhook de mutation, conteneur d'initialisation, `PYTHONPATH`).
- Comparer objectivement les deux approches (spans, attributs, surcoût, maîtrise des versions, sécurité).
- Constater la double instrumentation et savoir l'éviter.
- Décider et écrire pourquoi.

**Prérequis** : M23-E04 ; M14-E07 (MédiAgenda dans `wb-essais`).
**Durée indicative** : 1 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Ressource | `Instrumentation` **`python-essai`** dans `wb-essais` ; image `autoinstrumentation-python:0.66b1` par le cache `ghcr` de Harbor ; export OTLP **HTTP** vers l'agent (port 4318) |
| Copie | Deployment `mediagenda-auto` (+ PostgreSQL et Valkey jetables), image `<VERSION-SANS-TRACES>`, `OTEL_SERVICE_NAME=mediagenda-essai-auto` |
| Annotations | `instrumentation.opentelemetry.io/inject-python: "python-essai"`, `instrumentation.opentelemetry.io/container-names: "api"` |
| Livrable | `docs/observabilite/traces/auto-instrumentation.md` |

**Travail demandé**

1. Écris la ressource `Instrumentation` (point d'envoi, propagateurs, échantillonneur, attributs de ressource, contexte de sécurité du conteneur injecté compatible avec la Pod Security de `wb-essais`, exclusion des sondes, conventions stables, ni métriques ni journaux exportés).
2. Déploie la copie annotée (à la main : `wb-essais` est l'espace des essais). Décris ce que le webhook a changé dans le pod (`kubectl get pod -o yaml` : conteneur d'initialisation, volume, variables) et ce que coûte le démarrage.
3. Génère du trafic sur la copie et compare, sur une **création de rendez-vous**, la trace de la copie et celle de dev (M23-E04) : spans, noms, attributs, portées, ce qui manque.
4. Mesure la mémoire du conteneur `api` au repos et sous un peu de charge, dans les deux cas.
5. **Double instrumentation** : change l'image de la copie pour la version instrumentée de M23-E04 (sans retirer l'annotation). Que se passe-t-il (journaux du pod, spans) ? Retire l'annotation.
6. Écris `auto-instrumentation.md` : tableau comparatif, double instrumentation, décision argumentée, cas où l'auto-instrumentation est acceptable, ce qu'il en est de Go (et pourquoi c'est écarté chez nous), nettoyage. Puis **retire l'essai** (copie, base, cache, `Instrumentation`, Secret).

**Critères de réussite**
- [ ] Tempo a (eu) des traces de `mediagenda-essai-auto`, avec des spans PostgreSQL.
- [ ] Aucune `Instrumentation` hors de `wb-essais`, aucune annotation d'injection sur les espaces applicatifs.
- [ ] `auto-instrumentation.md` est sur `main` : comparaison, surcoût mesuré, double instrumentation, décision.

**Vérification** : `lab/bin/check 23 07` (valable avant ou après le retrait de l'essai)

<details><summary>Indice 1</summary>

L'annotation est lue **à la création du pod** par le webhook de mutation de l'opérateur : elle se pose sur le gabarit du Deployment (`spec.template.metadata.annotations`), pas sur le Deployment. Si rien n'est injecté, regarde les événements du ReplicaSet et les journaux de l'opérateur.
</details>

<details><summary>Indice 2</summary>

L'image d'auto-instrumentation Python exporte en OTLP **HTTP** (protobuf) : un point d'envoi en `:4317` ne fonctionne pas. Le SDK y démarre par `sitecustomize.py`, avant ton code : si ton code installe aussi un fournisseur, lequel gagne ?
</details>

**Pour aller plus loin** (facultatif) : lis la page de l'opérateur sur l'auto-instrumentation **Go** (eBPF) : quels droits demande le conteneur injecté ? Compare avec OBI/Beyla (annexe découverte du palier 3).

---

### M23-E08 — Corrélation : exemplars, `trace_id` dans les journaux, liens Grafana  `LAB` `★★★`

> **Ticket DEV-2408** — *De : Nadia Roussel* — *Copie : Julien Petit*
> Cette nuit encore : un pic de latence sur le graphe, une erreur dans les journaux, et vingt minutes pour retrouver la requête. Je veux trois clics : du point du graphe à la trace, de la trace à ses journaux, d'une ligne de journal à sa trace. Pour MédiAgenda et pour MédiDoc.

**Objectifs pédagogiques**
- Écrire `trace_id` et `span_id` dans les journaux JSON des deux applications, au format W3C.
- Les ranger en **métadonnées structurées** dans Loki (jamais en étiquettes) et en faire des liens Grafana (champs dérivés).
- Poser des **exemplars** sur les histogrammes de latence et les faire exploiter par Prometheus et Grafana.
- Déclarer tous les liens par code (sources Grafana).

**Prérequis** : M23-E06 ; M22-E06 (métadonnées structurées, `request_id`), M22-E02 (`sources-loki.yaml`), M21 (kps, Thanos Query).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Format | `trace_id` : 32 caractères hexadécimaux minuscules ; `span_id` : 16 ; champs JSON de premier niveau, à côté de `request_id` |
| Loki | métadonnées structurées `trace_id`, `span_id` dans les deux pipelines (`stage.match`) de MédiAgenda et MédiDoc de `alloy/config.alloy` ; liste fermée d'étiquettes du M22 inchangée |
| Sources Grafana | `grafana/sources-loki.yaml` (champs dérivés sur `loki-mediagenda` et `loki-medidoc`), `grafana/sources-tempo.yaml` (lien vers Loki), source Prometheus de kps (`grafana.sidecar.datasources.exemplarTraceIdDestinations`) |
| Exemplars | histogrammes `mediagenda_http_request_duration_seconds` et `medidoc_http_request_duration_seconds`, étiquette `trace_id` ; format **OpenMetrics** obligatoire ; Prometheus 3.15 : fonctionnalité `exemplar-storage` (`prometheus.prometheusSpec.enableFeatures` de kps) |
| Livrable | `docs/observabilite/traces/correlation.md` |

**Travail demandé**

1. **MédiAgenda** : le formateur JSON ajoute `trace_id` et `span_id` de la span courante (rien hors requête) ; l'histogramme de durée reçoit l'exemplar de la trace (seulement si elle est échantillonnée) ; `/metrics` répond en OpenMetrics quand Prometheus le demande (en-tête `Accept`), en texte sinon. Tests.
2. **MédiDoc** : un gestionnaire `slog` qui ajoute les deux identifiants aux lignes écrites **avec le contexte** de la requête ; les appels de journal des gestionnaires HTTP passent ce contexte ; exemplar sur l'histogramme ; OpenMetrics activé dans `promhttp`. Tests.
3. Livraison des deux applications (MR, CI, promotion dev puis recette).
4. **Alloy** : extraire les deux champs et les ranger en métadonnées structurées. Vérifie dans Explore (Loki) qu'un filtre `| trace_id = "…"` retrouve les lignes d'une trace.
5. **Grafana** : champ dérivé « label » `trace_id` → source `tempo` sur les deux sources Loki d'application ; `tracesToLogsV2` sur la source Tempo (filtre par espace de la span et par identifiant de trace) ; `exemplarTraceIdDestinations` sur la source Prometheus ; `exemplar-storage` dans kps. Tout par MR.
6. **Essaie les trois chemins** : un graphe de p95 de MédiAgenda avec les exemplars affichés → trace ; la trace → journaux ; une ligne de journal → trace. Note ce qui ne marche pas toujours, et pourquoi (pense au M23-E09 qui arrive).
7. Écris `correlation.md` (chemins, formats, où c'est configuré, limites).

**Critères de réussite**
- [ ] Des lignes de `mediagenda-dev` (locataire `mediagenda`) et de `medidoc-dev` (locataire `medidoc`) portent la métadonnée structurée `trace_id` ; `trace_id` n'est pas une étiquette Loki.
- [ ] Les sources Grafana déclarent les trois liens (champ dérivé vers `tempo`, `tracesToLogsV2`, `exemplarTraceIdDestinations`).
- [ ] Le Prometheus du cluster a `exemplar-storage` ; l'API des exemplars renvoie des `trace_id` pour MédiAgenda.
- [ ] `correlation.md` est sur `main`.

**Vérification** : `lab/bin/check 23 08`

<details><summary>Indice 1</summary>

En Python, `trace.get_current_span().get_span_context()` donne `trace_id` et `span_id` (entiers : formate-les en hexadécimal sur 32 et 16 caractères) ; `is_valid` est faux hors span. `prometheus_client` accepte `observe(valeur, exemplar={…})`, et `prometheus_client.exposition.choose_encoder` choisit le format d'après l'en-tête `Accept`.
</details>

<details><summary>Indice 2</summary>

En Go, `trace.SpanContextFromContext(ctx)` lit le contexte que `otelhttp` a posé dans la requête : un `slog.Handler` qui enveloppe le gestionnaire JSON peut l'ajouter dans `Handle(ctx, record)` — à condition que l'appel de journal passe `ctx` (`InfoContext`, `Log(ctx, …)`). Côté métriques : `prometheus.ExemplarObserver` et `promhttp.HandlerOpts{EnableOpenMetrics: true}`.
</details>

<details><summary>Indice 3</summary>

Un champ dérivé de type « Label » (`matcherType: label` dans le provisionnement) compare son expression aux **noms** des étiquettes, métadonnées structurées comprises ; le lien interne vers Tempo prend `${__value.raw}` comme requête (écrit `$${__value.raw}` dans un fichier provisionné). Pour les exemplars, si l'API de Thanos Query ne renvoie rien, interroge un pod Prometheus directement (`query_exemplars`) pour savoir de quel côté est le problème.
</details>

**Pour aller plus loin** (facultatif) : ajoute le lien trace → profil (`tracesToProfiles`), préparé ici, utilisé au M23-E14.

---

### M23-E09 — Échantillonnage en tête et en queue  `LAB` `★★★`

> **Ticket PLAT-2409** — *De : Karim Benali*
> Avec le trafic de la recette et de la production, Tempo va grossir vite, et 95 % de ces traces disent « tout va bien ». Règle : on garde **toutes** les traces en erreur, **toutes** celles de plus de 500 ms, et 10 % du reste. La passerelle passe à deux réplicas pour tenir la charge — et je ne veux pas de traces coupées en deux par ces deux réplicas.

**Objectifs pédagogiques**
- Distinguer échantillonnage en tête (SDK) et en queue (Collector), et les combiner sans perdre les erreurs.
- Configurer le processeur `tail_sampling` (politiques, mémoire, délai de décision).
- Router toutes les spans d'une trace vers le même réplica (exportateur `loadbalancing`, Service sans tête, résolveur et ses droits).
- Mesurer l'effet (métriques internes, volume dans Tempo) et en connaître les conséquences (exemplars, métriques tirées des traces).

**Prérequis** : M23-E08.
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Passerelle | `otel-passerelle` à **2 réplicas**, `tail_sampling` : `decision_wait` 10 s, mémoire de 20 000 traces, politiques `erreurs` (statut `ERROR`), `lentes` (500 ms), `reste-10-pourcent` (probabiliste 10 %) ; ressources à revoir (les traces attendent en mémoire) |
| Agents | exportateur `loadbalancing`, `routing_key: traceID`, vers le Service **sans tête** `otel-passerelle-collector-headless.traces` (port 4317) |
| Applications | `OTEL_TRACES_SAMPLER=parentbased_traceidratio` avec un ratio **explicite** (`OTEL_TRACES_SAMPLER_ARG`), dans les deux components `telemetrie` |
| Livrable | `docs/observabilite/traces/echantillonnage.md` |

**Travail demandé**

1. **Réfléchis d'abord** (dans le livrable) : quel ratio en tête, sachant la règle de Karim ? Que se passe-t-il, avec deux réplicas derrière un Service ordinaire, pour une trace dont les spans arrivent à des moments différents ?
2. **Les agents** : l'exportateur `loadbalancing` et son résolveur (lis sa documentation : `dns` ou `k8s`, et ce qu'il faut à ce dernier en droits) ; plus aucun envoi direct au Service ordinaire de la passerelle.
3. **La passerelle** : deux réplicas, budget de perturbation, répartition sur des nœuds différents, `tail_sampling` après `memory_limiter`, mémoire relevée.
4. **Les applications** : l'échantillonneur en tête explicite, par MR dans les deux dépôts de déploiement.
5. **Mesure** avec le générateur de trafic (dev) : décisions par politique et refus éventuels dans les métriques internes ; nombre de traces de `mediagenda-api` dans Tempo sur 10 minutes, avant et après ; une trace en erreur et une trace lente sont-elles toujours là ? Essaie ensuite, en dev seulement et le temps de l'essai, un ratio en tête de 0,25 : que perds-tu ? Remets 1,0.
6. Écris `echantillonnage.md` : règle, raisons, réglages, métriques à surveiller, conséquences (exemplars de M23-E08, métriques tirées des traces au M23-E13).

**Critères de réussite**
- [ ] `otel-passerelle` : 2 réplicas disponibles ; `tail_sampling` avec les trois politiques, après `memory_limiter`.
- [ ] `otel-agent` : `loadbalancing` par `traceID` vers le Service sans tête ; plus d'export direct au Service ordinaire.
- [ ] Les deux components `telemetrie` fixent `parentbased_traceidratio` et son ratio.
- [ ] Des décisions d'échantillonnage sont prises (métriques du `tail_sampling`) ; aucune trace décidée trop tôt.
- [ ] `echantillonnage.md` est sur `main`.

**Vérification** : `lab/bin/check 23 09`

<details><summary>Indice 1</summary>

La décision en tête est prise au début de la requête, avant de savoir si elle échouera. `parentbased_…` : un service appelé suit la décision de son appelant, sinon les traces se trouent.
</details>

<details><summary>Indice 2</summary>

Le résolveur `k8s` lit des **EndpointSlices** : sans droit `get/list/watch` dans l'espace `traces`, sa liste reste vide et l'agent écrit « couldn't find the exporter for the endpoint "" ». Le résolveur `dns` n'a pas besoin de droits, mais réagit moins vite aux changements de réplicas.
</details>

<details><summary>Indice 3</summary>

Les métriques du processeur commencent par `otelcol_processor_tail_sampling_` : `…global_count_traces_sampled` (par décision), `…sampling_trace_dropped_too_early` (mémoire trop petite), `…sampling_traces_on_memory`.
</details>

**Pour aller plus loin** (facultatif) : lis la proposition d'OpenTelemetry sur l'échantillonnage cohérent (`tracestate` `ot=th:…`) et ce que Tempo 3.1 en fait dans ses requêtes de métriques (`with(extrapolate=true)`).

---

### M23-E10 — Les pipelines du Collector : processeurs et données sensibles  `LIBRE` `★★★`

> **Ticket SEC-2410** — *De : Sophie Laurent* — *Copie : Claire Morel*
> J'ai lu des traces de recette. J'y ai trouvé le nom d'un fichier joint, qui contenait le nom d'une patiente, dans un paramètre d'URL. Les équipes corrigent leur code, mais je veux un filet **avant** que la donnée quitte le nœud : rien de ce qui ressemble à une donnée de santé ne doit arriver dans Tempo. Profitez-en pour ne plus stocker les sondes de qui que ce soit, et pour que chaque span dise d'où elle vient.

**Objectifs pédagogiques**
- Concevoir un pipeline de traitement : filtrage, masquage par règles et par motifs, enrichissement, transformation OTTL.
- Choisir **où** traiter (agent, passerelle) et dans quel ordre.
- Prouver l'absence de données interdites par des requêtes sur les données réelles.

**Prérequis** : M23-E09.
**Durée indicative** : 2 h.

**Contexte technique** : les données à protéger sont celles listées par `conventions-telemetrie.md` (M23-E04) ; les traces arrivent des SDK (conventions stables pour nos applications, anciennes conventions possibles pour d'autres émetteurs, comme l'auto-instrumentation de M23-E07) ; les composants de la distribution contrib 0.161 sont disponibles (`filter`, `transform`, `attributes`, `redaction`, `k8sattributes`, `resourcedetection`…).

**Travail demandé**

Conçois et livre (MR sur `plateforme/observabilite`) les traitements qui garantissent, pour toute span venue d'un pod du cluster :
- aucune span de sonde ou de collecte (`/sante`, `/pret`, `/metrics`, `/healthz`, `/readyz`), quelle que soit la convention de l'émetteur ;
- aucun paramètre d'URL conservé ;
- aucun littéral dans le texte des requêtes SQL ;
- aucun en-tête HTTP capturé ;
- aucune valeur d'attribut qui ressemble à un NIR ou à une adresse de courriel, quel que soit l'attribut, avec une trace de ce masquage ;
- l'origine de chaque span connue (espace, pod, Deployment, nœud, cluster, équipe), sans attribut à cardinalité inutile ;
- aucune régression : mémoire d'abord, envoi par lots en dernier, échantillonnage en queue intact.

Prouve-le par des données de test **factices** que tu envoies toi-même, puis par des requêtes TraceQL sur la dernière heure de données réelles. Complète `conventions-telemetrie.md` : ce que fait le Collector, ce qu'il ne couvre pas, les requêtes de contrôle.

**Critères de réussite**
- [ ] L'agent porte au moins un filtre et une réécriture d'attributs dans son pipeline, sans perdre `memory_limiter` en tête ni l'enrichissement.
- [ ] Sur la dernière heure, avec du trafic : aucune span de sonde, aucun `url.query` ni `?` dans les URL, aucun littéral SQL, aucun en-tête capturé, aucun attribut de patient.
- [ ] `conventions-telemetrie.md` décrit le masquage et ses limites.

**Vérification** : `lab/bin/check 23 10`

**Pour aller plus loin** (facultatif) : le même filet pour les spans qui arrivent par 10.10.41.63 sans passer par un agent (M23-E16).

---

### M23-E11 — Revue : la configuration du Collector du stagiaire  `REV` `★★`

> **Ticket PLAT-2411** — *De : Karim Benali*
> Lucas a ouvert une MR « collectors-v2 » : il a « simplifié » nos deux Collectors et branché l'outil de traces qu'InfoGér nous prête pour la migration. Il dit que ça marche sur son kind. Fais la revue, par écrit, avant que quelqu'un ne la fusionne.

**Objectifs pédagogiques**
- Relire une configuration de Collector et de son déploiement : sûreté (mémoire, pertes), exactitude (échantillonnage, noms), sécurité (exposition, données, tiers), exploitabilité (métriques, sondes).
- Hiérarchiser les constats et proposer une correction pour chacun.

**Prérequis** : M23-E10.
**Durée indicative** : 1 h.

**Contexte technique** : la proposition est dans [`ressources/E11-collector-lucas/otel-lucas.yaml`](../ressources/E11-collector-lucas/otel-lucas.yaml). Elle est **valide** pour le Collector (elle démarre) : ses défauts sont ailleurs. Ne l'applique pas.

**Travail demandé**

1. Relis le fichier. Pour chaque défaut : où, ce qui se passera en production, gravité (bloquant, majeur, mineur), correction. Au moins dix constats.
2. Note ce que la proposition fait bien.
3. Écris la revue dans `docs/observabilite/traces/revue-collector-lucas.md` (un tableau numéroté), MR sur `plateforme/medisphere`, décision sur la MR de Lucas.

**Critères de réussite**
- [ ] La revue compte au moins dix constats numérotés et traite au moins : la mémoire, l'équilibrage de l'échantillonnage en queue, les noms des exportateurs, l'exportateur `debug`, le chiffrement et l'envoi à un tiers, les droits de `k8sattributes`.
- [ ] La proposition n'a pas été appliquée ; aucun Collector n'utilise d'image `latest` ou hors de Harbor.

**Vérification** : `lab/bin/check 23 11`

<details><summary>Indice 1</summary>

Lis chaque bloc avec trois questions : que se passe-t-il quand la charge double ? que voit un attaquant sur le réseau du lab ? qu'est-ce qui part hors de MédiSphère ?
</details>

<details><summary>Indice 2</summary>

Lance-la sur ton poste avec le binaire `otelcol-contrib` 0.161 (en changeant les adresses d'écoute pour `127.0.0.1`) : le Collector lui-même te signale deux défauts au démarrage.
</details>

---

### M23-E12 — Trouver où passe le temps  `LAB` `★★★`

> **Ticket INC-5012** — *De : Nadia Roussel*
> L'API de recette est lente sur une partie des opérations. Pas d'erreur, `/pret` répond, les pods ne redémarrent pas. Tu as maintenant les traces : trouve où passe le temps, corrige, et écris ta démarche pour que l'astreinte sache le refaire.

**Objectifs pédagogiques**
- Passer du symptôme (métriques) à la requête lente (traces), puis à la span fautive et à sa cause, sans hypothèse préalable.
- Confirmer la cause avec les outils du composant concerné (PostgreSQL ou Valkey) avant de corriger.
- Tenir un journal de diagnostic exploitable.

**Prérequis** : M23-E05 à M23-E10.
**Durée indicative** : 1 h 30 (temps cible du diagnostic : 30 min).

**Contexte technique** : la lenteur est injectée par `lab/bin/break 23 12` (ne lis pas le script). Elle ne supprime aucune donnée. Pour générer de la charge sur la recette, réutilise `ressources/E05-trafic/trafic.sh` avec un port-forward de `svc/mediagenda` de `mediagenda-recette`. Si tu abandonnes : `lab/bin/break 23 12 --annuler`.

**Travail demandé**

1. Injecte la lenteur, génère du trafic sur la recette.
2. Diagnostique en partant des métriques (quelles routes ?), puis des traces (quelles spans ?), puis du composant (pourquoi ?). Chaque étape consignée avec l'heure, la commande ou la requête, le constat.
3. Corrige la cause (avec l'accord de Julien : c'est la recette).
4. Constate le retour à la normale par les mêmes requêtes, avec du trafic.
5. Écris le journal de diagnostic `docs/kubernetes/journal/AAAA-MM-JJ-INC-5012-<titre>.md` : chronologie, cause, correction, prévention, ce que les traces ont apporté.

**Critères de réussite**
- [ ] La lenteur n'est plus active (et pas par `--annuler`).
- [ ] Avec du trafic récent sur la recette : aucune span PostgreSQL de plus de 300 ms, aucune span Valkey de plus de 200 ms, aucune requête serveur de plus de 300 ms.
- [ ] Le journal de diagnostic INC-5012 est sur `main` de `plateforme/medisphere` (traces, spans, cause, prévention).

**Vérification** : `lab/bin/check 23 12`

<details><summary>Indice 1</summary>

Commence large : `{ resource.deployment.environment.name = "recette" && kind = server && duration > 300ms }`. Dans les traces trouvées, quelle span **fille** occupe le temps ? Ensuite, `| select(…)` pour voir l'attribut qui t'intéresse sur toutes.
</details>

<details><summary>Indice 2</summary>

Une span de base de données lente ne dit pas *pourquoi* : sur le primaire PostgreSQL, `pg_stat_activity` (colonnes `wait_event_type`, `wait_event`) dit si la session attend un verrou, un disque ou autre chose ; `\d` d'une table montre ses index et ses déclencheurs. Pour Valkey, `INFO commandstats` compte chaque commande reçue.
</details>

**Pour aller plus loin** (facultatif) : écris le runbook « l'API est lente » (RB-23x, palier 3) à partir de ton journal.
