# Module 23 — Palier 1 : Découverte

Une trace se construit à trois endroits : dans l'application (qui crée les spans et propage le contexte), dans les Collectors (qui reçoivent, enrichissent, relaient) et dans le stockage (qui indexe et répond aux requêtes). Ce palier monte la chaîne dans cet ordre inverse, pour qu'à chaque étape quelque chose de visible arrive au bout : l'opérateur OpenTelemetry et ses deux Collectors d'abord, avec des spans synthétiques ; Tempo sur le RGW ensuite ; puis MédiAgenda, instrumentée dans son code et livrée par le chemin habituel ; enfin le langage TraceQL pour interroger ce que tu as collecté.

Prérequis : modules 21 et 22 terminés (`lab/bin/check 22 25` vert) ; module 20 (Argo CD, `plateforme/charts-miroir`, promotion par MR) ; module 19 (pipeline de `mediagenda/api`). Lis [`00-introduction.md`](00-introduction.md), en particulier les règles du module.

---

### M23-E01 — Test de positionnement : traces distribuées  `Q` `★★`

> **Ticket PLAT-2401** — *De : Karim Benali*
> Avant de déployer quoi que ce soit : une heure, par écrit, sans moteur de recherche ni IA. Je veux savoir si tu sais ce qu'est une span avant qu'on parle de Collectors. Réponds même là où tu hésites.

**Objectifs pédagogiques**
- Évaluer tes acquis sur les traces distribuées (modèle de données, propagation, échantillonnage, OTLP, Collector).
- Repérer les notions à travailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 14 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

1. Qu'est-ce qu'une **trace**, une **span**, une span **racine** ? Cite six informations que porte une span.

2. *(QCM)* MédiAgenda reçoit `POST /api/v1/rendez-vous`, interroge PostgreSQL deux fois puis efface deux clés de Valkey. Combien de spans au minimum, et de quel type (*kind*) ?
   - A. Une span `SERVER` : le reste est dans les attributs
   - B. Une span `SERVER` et quatre spans `CLIENT`, filles (directes ou non) de la première
   - C. Cinq spans `INTERNAL` sœurs
   - D. Une trace par appel, reliées par le `request_id`

3. Différence entre un **attribut de ressource** et un **attribut de span** ? Où ranges-tu `service.name`, `http.response.status_code`, `k8s.pod.name`, `deployment.environment.name` ?

4. Décris ce que contient l'en-tête **`traceparent`** et qui le lit, qui l'écrit, quand MédiAgenda appelle MédiDoc. Que se passe-t-il si un relais HTTP entre les deux supprime cet en-tête ?

5. *(QCM)* Un service A propage en W3C (`traceparent`), le service B qu'il appelle n'accepte que le format B3. Résultat ?
   - A. Une seule trace : les formats sont équivalents
   - B. Deux traces distinctes : B démarre une nouvelle trace
   - C. Une erreur 400 renvoyée par B
   - D. Les spans de B sont rattachées à A par leur horodatage

6. Qu'est-ce que le **baggage** ? Donne un usage légitime et un risque (pense aux données de santé).

7. Qu'apporte un **Collector** entre l'application et le stockage, plutôt qu'un envoi direct du SDK vers Tempo ? Cite au moins quatre raisons.

8. Pourquoi deux niveaux de Collectors (un **agent** par nœud et une **passerelle**) ? Que fait chacun ?

9. *(QCM)* L'équipe veut garder 100 % des traces en erreur et 10 % des autres. Où décider ?
   - A. Dans le SDK, avec `traceidratio` à 0,1
   - B. Dans un Collector, après avoir vu toute la trace (échantillonnage en queue)
   - C. Dans Tempo, par la rétention
   - D. Dans Grafana, par un filtre de recherche

10. Qu'est-ce qu'**OTLP** ? Sur quels ports et transports ? Pourquoi est-ce important qu'il soit normalisé ?

11. Que sont les **conventions sémantiques** ? Pourquoi `http.status_code` et `http.response.status_code` peuvent-ils coexister dans un même système, et quel problème cela pose-t-il aux requêtes ?

12. Instrumentation **dans le code** ou **automatique** : deux avantages et deux inconvénients de chacune.

13. Une span a-t-elle sa place dans une **métrique**, et une métrique dans une span ? Explique ce qu'est un **exemplar**, puis comment relier une ligne de journal à une trace.

14. Pourquoi les traces sont-elles plus **dangereuses** que les métriques pour les données de santé ? Donne trois endroits où une donnée de patient peut se glisser dans une trace sans que personne ne l'ait voulu.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 14 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse (0, 1 ou 2 points) avec la grille du corrigé et calculé ton score sur 28.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour la propagation, suis une requête : qui crée le contexte, comment il franchit le réseau, qui le reprend, et ce qui se passe à chaque frontière (processus, protocole, relais).
</details>

<details><summary>Indice 2</summary>

Pour l'échantillonnage, demande-toi **quand** la décision est prise et ce que l'on sait de la requête à ce moment-là.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M23-E25) sans relire le corrigé.

---

### M23-E02 — L'opérateur OpenTelemetry et le Collector  `LAB` `★★`

> **Ticket PLAT-2402** — *De : Karim Benali* — *Copie : Claire Morel*
> Première brique : l'opérateur OpenTelemetry et deux Collectors, dans l'espace `traces`, par Argo CD comme le reste de l'observabilité. Un agent par travailleur, une passerelle. Pas encore de stockage : je veux voir des spans arriver à la passerelle (un exportateur `debug` en résumé, le temps de l'essai), et les métriques internes des Collectors dans Prometheus. L'entrée 10.10.41.63 est réservée dans le plan : publie-la, mais seul MGMT y a accès tant qu'elle n'a ni TLS ni authentification.

**Objectifs pédagogiques**
- Recopier un chart tiers dans Harbor et le déployer par une Application Argo CD multi-sources.
- Comprendre le rôle de l'opérateur (CRD `OpenTelemetryCollector`, webhooks, objets qu'il fabrique).
- Écrire la configuration d'un Collector : récepteurs, processeurs (ordre), exportateurs, pipelines, télémétrie interne.
- Faire parler une application à l'agent de **son** nœud, et ouvrir les flux réseau nécessaires (et seulement eux).

**Prérequis** : M20-E13 (`charts-miroir`), M21-E02 (sélecteur `medisphere.internal/supervision: "oui"`, ClusterRole `wb-checks-observabilite`), M15 (LB IPAM, CiliumNetworkPolicy), M14-E18 (politique `medisphere-images`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `open-telemetry/opentelemetry-operator` **0.126.1** (opérateur 0.161.0), dépôt amont `https://open-telemetry.github.io/opentelemetry-helm-charts` ; empreinte : champ `digest` de l'index amont |
| Opérateur | Application **`opentelemetry-operator`** (projet `plateforme`), espace `opentelemetry-operator-system`, values `plateforme/observabilite/otel/operateur/values.yaml` ; certificats des webhooks par **cert-manager** |
| Collectors | Application **`otel`** → dossier `otel/` de `plateforme/observabilite` (kustomize) ; espace **`traces`** (Pod Security `restricted`) ; CR **`otel-agent`** (`mode: daemonset`, compte de service `otel-agent`) et **`otel-passerelle`** (`mode: deployment`, 1 réplica) ; image contrib 0.161.0 par le cache `dockerhub` de Harbor |
| Pipeline de l'agent | `otlp` (4317, 4318) → `memory_limiter`, `k8sattributes`, `resourcedetection`, `batch` → passerelle (`otel-passerelle-collector.traces.svc.cluster.local:4317`) |
| Pipeline de la passerelle | `otlp` → `memory_limiter`, `batch` → `debug` (**résumé**, échantillonné ; retiré en M23-E03) |
| Point d'envoi des applications | `http://otel-agent-collector.traces.svc.cluster.local:4317` (Service créé par l'opérateur) |
| Entrée externe | Service **`otlp-externe`**, `LoadBalancer` à adresse demandée **10.10.41.63**, `externalTrafficPolicy: Local`, nom `otlp.apps.par1.medisphere.internal` (ExternalDNS), ports 4317/4318 vers la passerelle |
| Politiques | CNP `traces-agent` et `traces-passerelle` (entrées) ; sortie des espaces `mediagenda-*`, `medidoc-*`, `wb-essais` vers l'agent : **politique de cluster** (les AppProjects des équipes ne gèrent pas les politiques de la plateforme) |
| Générateur d'essai | [`ressources/E02-essai/telemetrygen.yaml`](../ressources/E02-essai/telemetrygen.yaml) (Job dans `wb-essais`) |

**Travail demandé**

1. **Le chart.** Ajoute l'opérateur à `charts.yaml` de `plateforme/charts-miroir` (version exacte, empreinte relevée et vérifiée), MR, pipeline vert ; contrôle sa présence et sa signature dans Harbor `charts/`. Lis `values.yaml` du chart (`helm show values`) : repère les images, les webhooks, `createRbacPermissions`.
2. **L'opérateur.** Écris `otel/operateur/values.yaml` (images par Harbor, certificats par cert-manager, ServiceMonitor du gestionnaire avec l'étiquette de sélection, ressources, PriorityClass) et l'Application `opentelemetry-operator` dans `plateforme/gitops/plateforme/`. Rends le chart en local avant la MR. Une fois synchronisée : liste les CRD installées, les webhooks et le certificat.
3. **L'agent.** Dans `plateforme/observabilite/otel/` : l'espace `traces`, le compte de service `otel-agent` et ses droits en **lecture** (ce que `k8sattributes` doit lire, et seulement cela), le CR `otel-agent`. Contraintes : le récepteur doit être joignable depuis les autres pods ; `memory_limiter` en premier ; l'agent ne surveille que les pods de son nœud ; métriques internes exposées sur 8888 ; contexte de sécurité compatible `restricted`.
4. **La passerelle.** Le CR `otel-passerelle`, avec l'exportateur `debug` en `verbosity: basic`, échantillonné.
5. **Le réseau.** Le Service `otlp-externe` ; les deux CNP d'entrée ; la politique de sortie des espaces applicatifs ; un ServiceMonitor pour les Services `…-monitoring` créés par l'opérateur. L'Application `otel`.
6. **Observe ce que l'opérateur a fabriqué** : DaemonSet, Deployment, Services (quatre pour la passerelle), ConfigMaps. Que vaut `internalTrafficPolicy` du Service de l'agent, et pourquoi ?
7. **Envoie des spans.** Lance le Job `telemetrygen-essai`, puis constate leur arrivée : journaux de la passerelle (exportateur `debug`), métrique `otelcol_receiver_accepted_spans` dans Prometheus pour l'agent **et** la passerelle. Depuis `adm01`, envoie aussi **une** span à la main en OTLP/HTTP JSON vers `http://10.10.41.63:4318/v1/traces` (`curl`, corps écrit par toi : un `resourceSpans` avec un `service.name`, un `traceId` de 32 caractères hexadécimaux, un `spanId` de 16, un nom et deux horodatages en nanosecondes).
8. **Documente** la chaîne dans `docs/observabilite/traces/architecture.md` (schéma, objets, flux, commandes de contrôle) et reporte les flux dans `docs/kubernetes/reseau/matrice-flux-cluster.md`.

**Critères de réussite**
- [ ] Applications `opentelemetry-operator` et `otel` `Synced` et `Healthy`.
- [ ] `otel-agent` : un pod prêt par travailleur ; `otel-passerelle` prête ; images de Harbor en 0.161.0.
- [ ] `memory_limiter` est le premier processeur des deux pipelines ; aucun exportateur nommé `otlp`/`otlphttp`.
- [ ] Le Service `otel-agent-collector` est en `internalTrafficPolicy: Local` ; `otlp-externe` a l'adresse 10.10.41.63 ; `adm01` joint 10.10.41.63:4317.
- [ ] `otelcol_receiver_accepted_spans` augmente pour la passerelle quand le Job tourne ; aucun refus.
- [ ] `architecture.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 23 02`

<details><summary>Indice 1</summary>

Depuis la 0.104 du Collector, un récepteur sans adresse explicite écoute sur `localhost` : le pod se parle à lui-même. Depuis la 0.12x, il en va de même des métriques internes. Les deux se règlent dans la configuration du CR, l'opérateur en déduit les ports des Services.
</details>

<details><summary>Indice 2</summary>

`k8sattributes` doit identifier le pod émetteur : par l'adresse source de la connexion (`pod_association`). Il lui faut lire des pods, des espaces, des ReplicaSets (pour remonter au Deployment). Le filtre `node_from_env_var` (avec `spec.nodeName` en variable) limite ce qu'il observe à son nœud. Pour la politique de sortie, cherche `enableDefaultDeny` dans la documentation des CiliumClusterwideNetworkPolicy : sans lui, la politique ferait passer en refus par défaut des pods qui n'en avaient pas.
</details>

<details><summary>Indice 3</summary>

Si les spans de l'agent n'arrivent pas à la passerelle, regarde `otelcol_exporter_send_failed_spans` et les journaux de l'agent, puis `hubble observe -n traces --verdict DROPPED`. Si l'Application `otel` échoue au premier passage, c'est souvent que les CRD de l'opérateur ne sont pas encore là : vague de synchronisation, ou réessai.
</details>

**Pour aller plus loin** (facultatif) : lis la page *Scaling the Collector* de la documentation d'OpenTelemetry : quand passer la passerelle en StatefulSet, quand ajouter un *Target Allocator* (pour les métriques, pas pour nos traces).

---

### M23-E03 — Tempo sur le RGW  `LAB` `★★`

> **Ticket PLAT-2403** — *De : Karim Benali*
> On remplace l'exportateur `debug` par un vrai stockage : Tempo 3.1, monolithique (on n'a ni la mémoire ni l'envie d'un Kafka), blocs dans le RGW de `ceph-par1` comme Thanos et Loki, quatorze jours de rétention **écrits** (le défaut du chart a changé, je ne veux pas le découvrir). La source Grafana par le code, comme celles de Loki.

**Objectifs pédagogiques**
- Préparer un stockage objet pour un composant : utilisateur RGW dédié, quota, compartiment, identifiants hors Git.
- Configurer Tempo 3 en monolithique sur S3 (TLS vérifié, style chemin, rétention) et comprendre ses composants.
- Brancher la passerelle sur Tempo avec une file d'attente et des reprises.
- Déclarer une source Grafana par code et chercher une trace.

**Prérequis** : M23-E02 ; M21-E24 ou M22-E02 (utilisateur RGW par composant, Secret par `secrets-k8s.sh`).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `grafana-community/tempo` **3.2.1** (Tempo 3.1.1) — le chart a **déménagé** de `grafana/` ; dépôt amont `https://grafana-community.github.io/helm-charts` |
| Application | **`tempo`**, projet `plateforme`, espace `traces` (créé par l'Application `otel`), values `plateforme/observabilite/tempo/values.yaml` |
| Stockage | utilisateur RGW **`tempo`** (quota 20 Gio), compartiment **`tempo-k8s-par1`**, point d'accès `rgw.par1.medisphere.internal` (HTTPS, certificat de la PKI MédiSphère) ; WAL sur un volume `ceph-rbd` de 10 Gio |
| Secrets | Secret `tempo-objstore` (clés `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), composant `tempo` de `plateforme/k8s/outils/secrets-k8s.sh`, Vault `critique` `secrets/tempo.yml` ; sur `adm01` `~/.config/workbook/s3-tempo.env` (600) |
| Racine de confiance | ConfigMap `racine-medisphere` (clé `medisphere-root-ca.crt`) dans `traces`, versionnée dans `otel/` |
| Rétention | **336 h** (14 jours) |
| Source Grafana | `grafana/sources-tempo.yaml` de `plateforme/observabilite` : ConfigMap `sources-tempo` (espace `supervision`, étiquette `grafana_datasource: "1"`), **uid `tempo`**, URL `http://tempo.traces.svc.cluster.local:3200` |

**Travail demandé**

1. **Le RGW.** Sur un nœud de `ceph-par1` : crée l'utilisateur `tempo` (quota activé), récupère ses clés **sans les afficher dans l'historique** et range-les dans `~/.config/workbook/s3-tempo.env` ; crée le compartiment avec cette identité depuis `adm01` ; ajoute le composant `tempo` à `secrets-k8s.sh` et le Secret dans Vault.
2. **Le chart.** Recopie `tempo` 3.2.1 par `charts-miroir`. Lis ses values : où se règlent le stockage, la rétention, les récepteurs, le volume ? Quel est le défaut de `tempo.retention` ?
3. **Les values.** Image par Harbor ; variables d'environnement développées dans la configuration (`-config.expand-env`) pour les clés ; S3 en style chemin vers le RGW avec la racine MédiSphère montée ; WAL sur volume ; rétention explicite ; ServiceMonitor ; contexte de sécurité `restricted`. Rends le chart, extrais `tempo.yaml` de la ConfigMap rendue et fais-le valider par le binaire de Tempo de la même version (`-config.verify`). L'Application `tempo`.
4. **La passerelle.** Remplace `debug` par un exportateur `otlp_grpc` vers Tempo (file d'attente, reprises). Ajoute la CNP `traces-tempo` (OTLP depuis la passerelle seulement ; 3200 depuis Grafana et Prometheus).
5. **La source Grafana.** Déclare-la par code (même modèle que `sources-loki.yaml`), avec un UID stable. Dans Explore, cherche les traces de `essai-telemetrygen` (relance le Job) et ouvre-en une.
6. **Sous le capot.** Après quelques minutes, liste le compartiment : quels objets Tempo y écrit-il, sous quel préfixe ? Lis le `meta.json` d'un bloc : format, nombre de traces, plage de temps. Dans les journaux de Tempo, repère le *live-store* et les tâches de l'ordonnanceur de compaction.

**Critères de réussite**
- [ ] Application `tempo` `Synced` et `Healthy` ; `/ready` répond `ready`.
- [ ] Configuration rendue : S3 `tempo-k8s-par1`, TLS vérifié, clés en `${…}`, `block_retention: 336h`.
- [ ] La passerelle exporte vers Tempo et n'a plus d'exportateur `debug`.
- [ ] Des blocs `…/data.parquet` existent sous `single-tenant/` dans le compartiment.
- [ ] Grafana trouve des traces de la dernière heure ; la source `tempo` est déclarée par code et saine.

**Vérification** : `lab/bin/check 23 03`

<details><summary>Indice 1</summary>

`radosgw-admin` tourne dans le conteneur d'outils de cephadm (`cephadm shell -- …`) sur un nœud de `ceph-par1`, comme au M08 et pour Thanos ou Loki. Pour ne pas laisser les clés dans l'historique, filtre la sortie JSON avec `jq` vers un fichier créé en 600.
</details>

<details><summary>Indice 2</summary>

Le chart définit `tempo.storage.trace.local` par défaut : une valeur `null` dans tes values retire une clé héritée. Il exige en revanche la clé `tempo.receivers.jaeger` (il en tire des ports) : ne la supprime pas, la CNP fera le tri.
</details>

<details><summary>Indice 3</summary>

Une trace n'est pas cherchable dans les secondes qui suivent son envoi : le *live-store* la garde le temps qu'elle soit complète, puis l'écrit dans son WAL ; le bloc n'arrive dans le RGW qu'ensuite. Si Grafana ne trouve rien, interroge Tempo directement (`kubectl -n traces port-forward svc/tempo 3200`, `curl 'localhost:3200/api/search?q={}'`) avant d'accuser la source.
</details>

**Pour aller plus loin** (facultatif) : lis la page *Deployment modes* de Tempo 3 : quels composants, quel rôle de Kafka en microservices, pourquoi le monolithique n'en a pas besoin.

---

### M23-E04 — Instrumenter MédiAgenda avec le SDK Python  `LAB` `★★`

> **Ticket DEV-2404** — *De : Julien Petit*
> On instrumente l'API nous-mêmes, dans le code : je veux voir chaque requête, chaque requête SQL, chaque accès à Valkey, et nos propres étapes (création d'un rendez-vous, calcul des créneaux). Contraintes de Sophie, non négociables : **aucune** donnée de patient dans les traces. Les réglages par les variables standard d'OpenTelemetry, pas par des `MEDIAGENDA_*` de plus. Ça part par MR, pipeline, et promotion GitOps : dev d'abord, recette ensuite.

**Objectifs pédagogiques**
- Initialiser le SDK OpenTelemetry Python (fournisseur, ressource, exportateur OTLP, envoi par lots) et l'arrêter proprement.
- Utiliser les bibliothèques d'instrumentation (FastAPI, psycopg, redis) et créer des spans métier sans données sensibles.
- Régler l'application par les variables `OTEL_*` posées par un component kustomize.
- Livrer par le chemin GitOps et constater les traces par environnement.

**Prérequis** : M23-E03 ; M19 (pipeline de `mediagenda/api`), M20 (promotion dev → recette par MR), M22-E06 (`request_id` dans les journaux).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Base de code | `mediagenda/api` tel que l'a laissé M22-E06 (journaux JSON avec `request_id`) : les modifications des M23-E06, E08 et E14 s'appliqueront ensuite dans cet ordre |
| Paquets | `opentelemetry-sdk` 1.45.x, `opentelemetry-exporter-otlp-proto-grpc` 1.45.x, `opentelemetry-instrumentation-fastapi`, `-psycopg`, `-redis` **0.66b1** (bornes `>=0.66b1,<0.67` : les instrumentations suivent le SDK) |
| Variables (component `components/telemetrie` de `mediagenda/deploiement`) | `OTEL_SERVICE_NAME=mediagenda-api` ; `OTEL_RESOURCE_ATTRIBUTES=service.namespace=medisphere,deployment.environment.name=<env>` ; `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-agent-collector.traces.svc.cluster.local:4317` ; `OTEL_TRACES_SAMPLER=parentbased_always_on` ; `OTEL_PROPAGATORS=tracecontext,baggage` ; `OTEL_SEMCONV_STABILITY_OPT_IN=http,database` |
| Environnement | l'étiquette `medisphere.internal/environnement` que chaque overlay pose sur le gabarit du pod |
| Spans métier attendues | `mediagenda.rendez_vous.creer`, `mediagenda.creneaux.calculer`, `mediagenda.cache.invalider` ; attributs préfixés `mediagenda.` |
| Version | une nouvelle version mineure de l'image (ex. `v1.1.0`) |

**Travail demandé**

1. **Le SDK.** Dans un module `telemetrie.py` de `mediagenda/api` : une fonction appelée **une fois** au démarrage, avant la création du pool PostgreSQL et du client Valkey, qui installe le fournisseur de traces (ressource issue de l'environnement + `service.version`), l'exportateur OTLP gRPC par lots si un point d'envoi est configuré, et instrumente psycopg et redis ; une fonction d'arrêt appelée après l'arrêt d'uvicorn.
2. **FastAPI.** Instrumente l'application en excluant `/sante`, `/pret` et `/metrics`. FastAPI 0.142 embarque sa propre télémétrie : lis ce qu'elle fait en présence de l'instrumentation contrib, et empêche-la d'ajouter un exportateur d'après les variables `OTEL_*`.
3. **Les spans métier**, avec leurs attributs : praticien, durée, identifiant du rendez-vous créé, résultat du cache (`hit`, `miss`, `erreur`), nombre de créneaux libres. Un conflit (409) est un **événement**, pas une erreur. Ni le patient ni le motif, nulle part.
4. **Les tests.** Ajoute des tests (fournisseur et exportateur en mémoire) : spans produites et reliées, sondes non tracées, contexte W3C repris d'un en-tête `traceparent`, aucune donnée patient dans les attributs. `uv run pytest`, `ruff` : verts.
5. **La livraison.** MR, pipeline (image signée), MR de promotion vers dev ouverte par la CI. Dans `mediagenda/deploiement`, crée le component `telemetrie` et inclus-le dans les overlays dev et recette (place : avant `components/livraison`). Vérifie le rendu (`kustomize build`) avant la MR.
6. **Constate.** Génère quelques requêtes en dev (port-forward ou nom publié), cherche les traces de `mediagenda-api` en dev dans Grafana, ouvre une création de rendez-vous : quelles spans, quels attributs de ressource (lesquels viennent de l'application, lesquels de l'agent) ? Promeus en recette par MR et vérifie de même.
7. **Documente** les conventions dans `docs/observabilite/traces/conventions-telemetrie.md` : ressource, variables, nommage des spans, attributs métier, statuts, interdits.

**Critères de réussite**
- [ ] `mediagenda/api` déclare le SDK et les instrumentations (verrou à jour) ; tests verts.
- [ ] Le component `telemetrie` existe et est inclus en dev et en recette ; les Deployments portent `OTEL_SERVICE_NAME` et `OTEL_RESOURCE_ATTRIBUTES`.
- [ ] Tempo a des traces récentes de `mediagenda-api` en dev **et** en recette, avec des spans PostgreSQL et Valkey, et la span `mediagenda.rendez_vous.creer` fille de la span serveur.
- [ ] Aucune sonde tracée ; aucun attribut de patient.
- [ ] `conventions-telemetrie.md` est sur `main`.

**Vérification** : `lab/bin/check 23 04`

<details><summary>Indice 1</summary>

`Resource.create()` lit déjà `OTEL_SERVICE_NAME` et `OTEL_RESOURCE_ATTRIBUTES` ; le `TracerProvider` lit `OTEL_TRACES_SAMPLER` ; l'exportateur OTLP lit `OTEL_EXPORTER_OTLP_ENDPOINT` (un schéma `http://` veut dire « sans TLS »). Ton code n'a presque rien à passer en paramètre.
</details>

<details><summary>Indice 2</summary>

`start_as_current_span` note l'exception et passe la span en erreur si une exception la traverse : pour un 409, lève l'`HTTPException` **après** la fin du bloc. Dans les tests, le fournisseur global ne se pose qu'une fois par processus : fais-le dans une *fixture* de module.
</details>

<details><summary>Indice 3</summary>

`$(VAR)` dans la valeur d'une variable d'environnement est remplacé par Kubernetes si `VAR` est définie **plus haut** dans la même liste ; `fieldRef` lit une étiquette du pod : `metadata.labels['medisphere.internal/environnement']`.
</details>

**Pour aller plus loin** (facultatif) : essaie la télémétrie native de FastAPI 0.142 sur une branche (sans l'instrumentation contrib) et compare les spans (noms, attributs, spans d'« opération »).

---

### M23-E05 — Explorer les traces dans Grafana : TraceQL  `LAB` `★★`

> **Ticket PLAT-2405** — *De : Nadia Roussel*
> Pour l'astreinte, j'ai besoin d'un carnet de requêtes TraceQL qui marchent sur nos données : les requêtes lentes, les erreurs, ce qui touche la base, le cache… Une par question, commentée, dans le dépôt, que je puisse copier à 3 h du matin.

**Objectifs pédagogiques**
- Écrire des requêtes TraceQL : sélection par ressource, par attribut de span, par intrinsèque (`duration`, `kind`, `status`, `name`, `trace:…`, `event:…`).
- Utiliser les opérateurs structurels (`>>`, `>`, `~`, `&&` entre ensembles) et les agrégats (`count()`, `avg()`, `select()`).
- Lire une trace dans Grafana (cascade, détails de span, graphe de nœuds) et en tirer un diagnostic.

**Prérequis** : M23-E04.
**Durée indicative** : 1 h 30.

**Contexte technique** : générateur de trafic varié (créations, doublons 409, introuvables 404, créneaux servis par la base puis par le cache) : [`ressources/E05-trafic/trafic.sh`](../ressources/E05-trafic/trafic.sh), à lancer contre dev (port-forward de `svc/mediagenda` de `mediagenda-dev`). Fichier attendu : `requetes/E05.traceql` de `plateforme/observabilite`, **une requête par ligne**, commentaires sur des lignes commençant par `#` ; les requêtes de métriques (facultatives) commentées, préfixées `# métrique`.

**Travail demandé**

1. Lance le générateur, puis, dans Explore (source `tempo`, onglet TraceQL), écris et enregistre une requête pour chacune des questions :
   1. toutes les traces de l'API en dev (attributs de **ressource**) ;
   2. les requêtes serveur de plus de 100 ms ;
   3. les réponses en erreur côté client ou serveur (attribut de span, conventions **stables**) ;
   4. les spans PostgreSQL de plus de 2 ms, avec le texte de la requête dans le résultat ;
   5. les appels de créneaux servis **sans** le cache ;
   6. les conflits de créneau (pense à ce que tu as fait en E04 d'un conflit) ;
   7. les requêtes serveur qui ont touché PostgreSQL (opérateur structurel) ;
   8. les commandes Valkey **directement** sous la span d'invalidation du cache ;
   9. les traces de plus de 4 spans de l'API ;
   10. les traces dont la racine est l'API et qui durent plus de 50 ms ;
   11. les traces qui contiennent un `POST` **et** une commande Valkey (sur deux spans différentes).
2. Pour deux résultats, ouvre la trace : lis la cascade, le chemin critique, les attributs de ressource de chaque span. Note dans un commentaire du fichier ce que tu en conclus (où passe le temps d'une création ?).
3. Facultatif : deux requêtes de **métriques** TraceQL (taux par route, p95 par route) dans l'onglet Metrics.
4. MR du fichier sur `plateforme/observabilite`.

**Critères de réussite**
- [ ] `requetes/E05.traceql` contient au moins 10 requêtes, dont au moins un opérateur structurel, un agrégat ou un `select`, et des intrinsèques.
- [ ] Chaque requête est acceptée par Tempo et renvoie au moins une trace sur les 24 dernières heures.

**Vérification** : `lab/bin/check 23 05`

<details><summary>Indice 1</summary>

Trois portées d'attributs : `resource.`, `span.`, et des **intrinsèques** sans préfixe (`name`, `kind`, `status`, `duration`) ou préfixés (`trace:duration`, `trace:rootService`, `event:name`). Un attribut avec des points s'écrit tel quel (`span.http.response.status_code`) ; avec un tiret, entre guillemets (`span."x-y"`).
</details>

<details><summary>Indice 2</summary>

`{ A } >> { B }` sélectionne les spans B qui ont un ancêtre A ; `{ A } > { B }`, les B enfants directs de A ; `{ A } && { B }`, les traces qui contiennent les deux. `| count() > 4` filtre les ensembles de spans par leur taille.
</details>

**Pour aller plus loin** (facultatif) : la page *TraceQL metrics* de Tempo, et la limite de ces requêtes sur des données échantillonnées (M23-E09).
