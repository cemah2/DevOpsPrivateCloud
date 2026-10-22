# Module 23 — Introduction : traces et profilage

## Où passe le temps ?

Mardi, 10 h 40. La revue d'incident de la semaine dernière tourne en rond. Les métriques du M21 disaient que la prise de rendez-vous de production avait un p95 de 1,8 s pendant vingt minutes ; les journaux du M22 montraient des requêtes lentes, mais aucune erreur ; personne n'a su dire si le temps passait dans la passerelle, dans l'API, dans PostgreSQL, dans Valkey ou dans MédiDoc. Claire Morel clôt la réunion par un message.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Traces distribuées — le troisième signal
>
> Bonjour,
>
> On a des métriques et des journaux corrects ; il nous manque la vue « requête par requête ». Julien propose **OpenTelemetry** : c'est un standard ouvert, porté par la CNCF, sans dépendance à un éditeur, et c'est ce que je veux. Ce que j'attends du module :
> 1. une chaîne de traces gérée **par le code** comme le reste de l'observabilité : l'opérateur OpenTelemetry, des **Collectors** (un agent par nœud, une passerelle), **Tempo** sur le RGW de `ceph-par1`, le tout par Argo CD ;
> 2. MédiAgenda et MédiDoc **instrumentées dans leur code**, par MR, livrées par le chemin habituel (CI, promotion GitOps) ;
> 3. une corrélation en un clic : d'un point de graphe à la trace, de la trace à ses journaux, du journal à la trace ;
> 4. un volume maîtrisé (échantillonnage) et **aucune donnée de santé** dans les traces : Sophie relira ;
> 5. les profils CPU et mémoire de l'API quand elle sature (Karim), et une comparaison honnête avec Jaeger.
>
> Nadia veut pouvoir répondre à « l'API est lente » en dix minutes, la nuit. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 23, MédiSphère a sa chaîne de traces **v1** (étiquette `traces-v1` de `plateforme/medisphere`) : avec les métriques (M21) et les journaux (M22), c'est la pile d'observabilité complète qu'utiliseront l'astreinte (F3), la sécurité à l'exécution (M26) et les tests de charge (M29).

- **OpenTelemetry Operator 0.161** (Application `opentelemetry-operator`, espace `opentelemetry-operator-system`) et deux **Collectors contrib 0.161** dans l'espace **`traces`** : `otel-agent` (un par travailleur) et `otel-passerelle` (un, puis deux réplicas) ; point d'entrée hors cluster **10.10.41.63** (`otlp.apps.par1.medisphere.internal`, 4317/4318) ;
- **Tempo 3.1** monolithique (Application `tempo`), blocs dans le compartiment RGW **`tempo-k8s-par1`**, rétention 14 jours, source Grafana `tempo` déclarée par code ;
- **MédiAgenda** (SDK Python) et **MédiDoc** (SDK Go) instrumentées dans le code, avec un vrai appel de l'une à l'autre (pièces jointes des rendez-vous) ; l'auto-instrumentation de l'opérateur essayée et comparée ;
- les liens métriques ↔ traces ↔ journaux, l'échantillonnage en tête et en queue, le filtrage et le masquage dans les Collectors ;
- au palier 3 : métriques tirées des traces, **Pyroscope 2.4**, Jaeger v2 en comparaison (retiré), TLS et authentification de l'entrée externe ; ADR-0230, runbooks RB-230 et suivants.

Le **palier 1** (ce fichier et `01-decouverte.md`) monte la chaîne (opérateur, Collectors, Tempo), instrumente MédiAgenda et t'apprend TraceQL. Le **palier 2** (`02-operationnel.md`) instrumente MédiDoc, compare l'auto-instrumentation, relie les trois signaux, échantillonne, protège les données, fait relire une configuration ratée et met tout cela au service d'un vrai diagnostic de lenteur.

## Architecture du module

```
   mediagenda-dev / -recette / -prod             medidoc-dev / -recette          adm01 (MGMT)
   ┌──────────────────────────────┐              ┌─────────────────────┐            │ OTLP 4317/4318
   │ API MédiAgenda (SDK Python)  │──HTTP───────▶│ MédiDoc (SDK Go)    │            │ (essais ; VMs au
   │  FastAPI, psycopg, redis,    │ traceparent  │  otelhttp, otelaws  │            │  M23-E16, en TLS)
   │  httpx                       │              │                     │            ▼
   └──────────────┬───────────────┘              └──────────┬──────────┘   10.10.41.63 (Service
                  │ OTLP gRPC 4317, sans TLS : http://otel-agent-collector.traces.svc:4317   otlp-externe)
                  │ (internalTrafficPolicy: Local → l'agent du MÊME nœud)                     │
   ═══════════════▼═════════════════ espace traces ═════════════════════════════════════════▼═══════
   otel-agent (DaemonSet, k8s-w01..03)                          otel-passerelle (1 puis 2 réplicas)
     memory_limiter → filtres → k8sattributes ──── OTLP ────▶     memory_limiter → tail_sampling (E09)
     → resourcedetection → masquage (E10) → batch  (traceID, E09)  → batch → otlp_grpc
                                                                        │ OTLP 4317
                                                                        ▼
                                                     Tempo 3.1 (StatefulSet, WAL sur ceph-rbd)
                                                        │ blocs Parquet (S3, TLS)    ▲ TraceQL (3200)
                                                        ▼                            │
                                    RGW ceph-par1 : tempo-k8s-par1        Grafana (supervision) :
                                    (10.10.30.200, par eth1)              sources tempo, loki-*, prometheus
```

Points structurants :

- **Un agent par nœud, une passerelle.** L'application ne parle qu'à l'agent de son nœud (le Service créé par l'opérateur pour un DaemonSet a `internalTrafficPolicy: Local`) : un aller-retour local, et l'agent connaît l'adresse du pod émetteur pour l'enrichir (`k8sattributes`). La passerelle centralise ce qui demande une vue globale : l'échantillonnage en queue, l'export vers Tempo, l'entrée externe.
- **Tempo 3 monolithique.** Un seul processus (distributeur, *live-store*, requêteur, ordonnanceur et travailleurs de compaction) : **pas de Kafka** (obligatoire en microservices, pas en monolithique). Les traces récentes sont dans le WAL du volume, les blocs (format Parquet) dans le RGW.
- **L'instrumentation est dans le code.** Les variables standard `OTEL_*` règlent tout (nom du service, attributs de ressource, point d'envoi, échantillonnage, propagation) : le code n'ajoute aucune variable maison, la plateforme les pose par un component kustomize `telemetrie` de chaque dépôt `…/deploiement`.
- **Tout est livré par Argo CD** (projet `plateforme`) : charts tiers recopiés par `plateforme/charts-miroir`, values et manifestes dans `plateforme/observabilite` (`otel/`, `tempo/`, `grafana/`), Applications dans `plateforme/gitops/plateforme/`. Les applications changent par MR, CI et promotion (M19, M20).

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**Trace et span.** Une **trace** raconte une requête de bout en bout. Elle est faite de **spans** : une opération nommée, avec un début, une durée, un statut (`UNSET`, `OK`, `ERROR`), un **type** (*kind* : `SERVER`, `CLIENT`, `INTERNAL`, `PRODUCER`, `CONSUMER`), des **attributs** (clé-valeur), des **événements** (instants notables) et une span **parente**. Toutes les spans d'une trace partagent un `trace_id` (16 octets) ; chacune a son `span_id` (8 octets).

**Ressource et portée.** La **ressource** décrit *qui* émet (`service.name`, `service.version`, `deployment.environment.name`, `k8s.pod.name`…) ; la **portée** (*instrumentation scope*), quelle bibliothèque a créé la span (`opentelemetry.instrumentation.psycopg`…).

**Contexte et propagation.** Pour qu'un appel de MédiAgenda à MédiDoc reste dans la même trace, le contexte (`trace_id`, `span_id` parent, décision d'échantillonnage) voyage dans l'en-tête HTTP **`traceparent`** (W3C Trace Context), éventuellement avec **`baggage`**. Côté client, l'instrumentation l'**injecte** ; côté serveur, elle l'**extrait**. Un relais qui supprime l'en-tête, ou deux services qui ne parlent pas le même format (W3C, B3…), coupent la trace en morceaux.

**SDK, API, instrumentation.** L'**API** OpenTelemetry est ce qu'appelle le code (créer une span) ; le **SDK** fournit le fournisseur de traces, les processeurs (envoi par lots), l'échantillonneur et l'**exportateur** (OTLP). Les **bibliothèques d'instrumentation** créent les spans des frameworks (FastAPI, psycopg, `net/http`, SDK AWS) ; l'**auto-instrumentation** les charge sans toucher au code (agent, `sitecustomize`, eBPF).

**OTLP.** Le protocole d'OpenTelemetry : Protobuf sur gRPC (4317) ou sur HTTP (4318, `/v1/traces`), ou JSON sur HTTP. Les SDK, les Collectors, Tempo et Jaeger le parlent tous.

**Collector.** Un programme de traitement : **récepteurs** → **processeurs** → **exportateurs**, assemblés en **pipelines** par signal. Distribution *core* (minimale) ou **contrib** (tous les composants : `k8sattributes`, `tail_sampling`, `loadbalancing`, `redaction`…). Depuis la 0.144, les exportateurs OTLP s'appellent **`otlp_grpc`** et **`otlp_http`** (`otlp` et `otlphttp` sont des alias dépréciés).

**Conventions sémantiques.** Les noms d'attributs normalisés (`http.request.method`, `http.response.status_code`, `url.path`, `db.system.name`, `db.query.text`…) qui rendent les traces comparables d'un langage à l'autre. Les conventions HTTP et base de données ont été stabilisées en changeant des noms : les instrumentations Python émettent encore les anciens par défaut (`OTEL_SEMCONV_STABILITY_OPT_IN` les fait passer aux nouveaux).

**Échantillonnage.** **En tête** (dans le SDK, au début de la requête, `parentbased_traceidratio`) : peu coûteux mais aveugle à l'issue de la requête. **En queue** (dans un Collector, après avoir vu toute la trace) : on garde les erreurs et les lentes, mais il faut que toutes les spans d'une trace arrivent au **même** Collector.

**TraceQL.** Le langage de requête de Tempo : `{ resource.service.name = "mediagenda-api" && duration > 200ms }` sélectionne des spans ; des opérateurs relient des ensembles de spans (`>>` descendant, `>` enfant, `~` sœur, `&&` dans la même trace) ; `| count()`, `| avg(duration)`, `| select(…)` agrègent ou enrichissent ; `| rate() by (…)` en fait des métriques.

**Profilage continu** (palier 3). Des échantillons de piles d'appels pris en permanence (CPU, allocations) et rangés comme des séries temporelles (Pyroscope) : la trace dit *quelle* requête est lente, le profil dit *quelle fonction* consomme.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | OpenTelemetry Operator **0.161.0** (chart `open-telemetry/opentelemetry-operator` **0.126.1**) ; Collector **contrib 0.161.0** ; Tempo **3.1.1** (chart `grafana-community/tempo` **3.2.1**) ; SDK Python `opentelemetry-sdk` **1.45.1**, instrumentations **0.66b1** ; SDK Go `go.opentelemetry.io/otel` **1.47.0**, `otelhttp`, `otelaws`, `autoprop` **0.72.0** ; `telemetrygen` **v0.161.0** ; Pyroscope 2.4 et Jaeger 2.22 au palier 3 |
| Changements de version | [`annexes/versions-bloc-DE.md`](../../../annexes/versions-bloc-DE.md), section « Traces et profilage » : exportateurs `otlp_grpc`/`otlp_http`, récepteurs et métriques internes sur `localhost` par défaut, Tempo 3 sans *ingester* ni *compactor* (*live-store*, ordonnanceur et travailleurs), rétention du chart 3.2 enfin appliquée (24 h par défaut : fixe-la), conventions sémantiques stables en Python sur option, et FastAPI 0.142 qui embarque sa propre télémétrie (voir M23-E04) |
| Images | toutes par Harbor (politique `medisphere-images`) : `registry.par1.medisphere.internal/ghcr/open-telemetry/opentelemetry-operator/opentelemetry-operator:0.161.0`, `…/dockerhub/otel/opentelemetry-collector-contrib:0.161.0`, `…/dockerhub/grafana/tempo:3.1.1`, `…/ghcr/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.66b1`, `…/ghcr/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.161.0` |
| Espaces | `opentelemetry-operator-system` (opérateur), **`traces`** (Collectors, Tempo, puis Pyroscope ; Pod Security `restricted`, créé par l'Application `otel`) |
| Services | `otel-agent-collector` (4317/4318, local au nœud), `otel-passerelle-collector` (+ `-headless`, `-monitoring` 8888), `tempo` (3200 HTTP, 4317/4318 OTLP), `otlp-externe` (LoadBalancer **10.10.41.63**, `otlp.apps.par1.medisphere.internal`) |
| Dépôts | `plateforme/charts-miroir` (`charts.yaml`) ; `plateforme/gitops` (`plateforme/opentelemetry-operator.yaml`, `otel.yaml`, `tempo.yaml`) ; `plateforme/observabilite` (`otel/`, `otel/operateur/values.yaml`, `tempo/values.yaml`, `grafana/sources-tempo.yaml`, `requetes/E05.traceql`) ; `mediagenda/api`, `medidoc/medidoc` (code) ; `mediagenda/deploiement`, `medidoc/deploiement` (component `telemetrie`) ; `plateforme/k8s` (`secrets/tempo.yml`, `outils/secrets-k8s.sh`) ; `plateforme/medisphere` (`docs/observabilite/traces/`) |
| Stockage objet | utilisateur RGW **`tempo`**, compartiment **`tempo-k8s-par1`** ; Secret `tempo-objstore` dans `traces` (hors Git, composant `tempo` de `secrets-k8s.sh`) ; sur `adm01` : `~/.config/workbook/s3-tempo.env` (600) |
| Attributs de ressource | `service.name` = `mediagenda-api` / `medidoc` ; `service.namespace=medisphere` ; `deployment.environment.name` = `dev` / `recette` / `prod` ; `k8s.*` et `medisphere.equipe` par l'agent |
| Grafana | sources par code (ConfigMaps `grafana_datasource: "1"` de `supervision`, comme au M22) : `tempo` (uid `tempo`), `loki-mediagenda`, `loki-medidoc`… (M22), `prometheus` (M21) |
| Documentation | `docs/observabilite/traces/` : `architecture.md`, `conventions-telemetrie.md`, `auto-instrumentation.md`, `correlation.md`, `echantillonnage.md`, `revue-collector-lucas.md`, puis ADR-0230 et RB-230… ; journaux de diagnostic dans `docs/kubernetes/journal/` |
| Tickets | `PLAT-24xx`, `DEV-24xx`, `SEC-24xx`, `INC-50xx` (xx = numéro de l'exercice) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel |
| `<VERSION-SANS-TRACES>` | La dernière étiquette de l'image `medisphere/mediagenda-api` publiée **avant** M23-E04 (ex. `v1.0.0`) |
| `<CLE-RGW-TEMPO>` | Clés de l'utilisateur RGW `tempo` (jamais dans un dépôt, ni dans un argument de commande) |

### Variables de `lab/lab.env`

Facultatives, avec des valeurs par défaut qui conviennent :

```
WB_M23_TEMPO_UID=tempo                                   # UID de la source Grafana Tempo
WB_M23_S3_TEMPO="$HOME/.config/workbook/s3-tempo.env"    # identifiants RGW de Tempo (lecture du compartiment par les checks)
WB_RGW_ENDPOINT=https://rgw.par1.medisphere.internal
```

Les checks du module lisent aussi Prometheus (`WB_PROM_URL`), Grafana (`grafana-checks.token`), Loki et GitLab comme aux M21 et M22, et le cluster avec le compte `wb-checks` (la ClusterRole `wb-checks-observabilite` du M21-E02 couvre déjà `opentelemetry.io`).

---

## Règles du module

1. **Jamais de donnée de santé dans une trace.** Pas de nom de patient, de motif, de contenu ou de nom de document, de paramètre SQL, d'en-tête d'authentification : ni en attribut, ni en nom de span, ni dans un événement. Les essais se font avec des données **factices** (`Essai-…`). Une fuite se corrige dans le code ; le masquage du Collector (M23-E10) n'est qu'un filet.
2. **Pas d'exportateur `debug` détaillé** ailleurs qu'en essai bref : il recopie chaque span dans les journaux du pod, donc dans Loki.
3. **Tout par le code.** Collectors, Tempo, sources Grafana : MR sur `plateforme/observabilite`, synchronisation par Argo CD. Code des applications : MR, CI, promotion GitOps (dev automatique, recette par MR approuvée, prod au mini-projet). Un `kubectl apply` direct n'est permis que dans `wb-essais`.
4. **Mémoire.** Profil des blocs D et E ≈ 100 Go. Ce module ajoute ≈ 3 Go (opérateur 0,25 Go, trois agents, passerelle 0,5 puis 2 × 1 Go, Tempo 1-2 Go), puis Pyroscope au palier 3. Jaeger (palier 3) ne tourne jamais en même temps qu'OpenSearch (M22) ou un autre composant temporaire.
5. **Entrée 10.10.41.63** : tant qu'elle n'a ni TLS ni jeton (jusqu'au M23-E16), elle n'est ouverte qu'au réseau MGMT et ne reçoit que des spans d'essai.
6. **Ne supprime jamais de données de `tempo-k8s-par1`** à la main (les scripts de panne ne le font pas non plus) : la rétention de Tempo s'en charge.

---

## Préparer l'environnement

Vérifie l'état d'entrée : le mini-projet du M22 (et donc celui du M21) doit être vert, Argo CD et le miroir de charts opérationnels, le RGW joignable.

```
admin@adm01:~$ lab/bin/check 22 25
admin@adm01:~$ lab/bin/check 21 46
admin@adm01:~$ kubectl get applications.argoproj.io -n argocd | grep -E 'kube-prometheus-stack|loki|alloy|observabilite'
admin@adm01:~$ kubectl get nodes
admin@adm01:~$ curl -sI --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://rgw.par1.medisphere.internal | head -1
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

Il te faut une dizaine de Go libres sur `pve01` au-delà du profil des blocs D et E. Vérifie aussi que les applications journalisent en JSON avec `request_id` (M22-E06) et que `aws` (M16) et `yq` sont sur `adm01`.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 23 <XX>`. Elles sont en lecture seule : objets du cluster avec `wb-checks`, recherches TraceQL dans Tempo par la source Grafana (ou par le mandataire de l'API), métriques des Collectors dans Prometheus, journaux dans Loki, dépôts GitLab en lecture, liste du compartiment RGW. Celles qui interrogent les traces récentes demandent du **trafic** : `ressources/E05-trafic/trafic.sh`.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M23-EXX/` : `observabilite/` reproduit `plateforme/observabilite`, `gitops/` `plateforme/gitops`, `deploiement-mediagenda/` et `deploiement-medidoc/` les dépôts de déploiement, `mediagenda-api/` et `medidoc/` des **correctifs** (`git apply`) sur le code des applications, `medisphere/` la documentation.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─┬─ E07
                                   ├─ E08 ─ E09 ─ E10 ─ E11
                                   └──────────────────────── E12
```

1. **E01** — à froid.
2. **E02 → E05** dans l'ordre : la chaîne, puis le stockage, puis la première application, puis les requêtes.
3. **E06** avant tout le reste du palier 2 (la trace distribuée sert partout).
4. **E07** (essai jetable) quand tu veux ; **E08 → E11** dans l'ordre ; **E12** en dernier.

Durée indicative : palier 1, 7 à 9 heures ; palier 2, 11 à 14 heures.

## Pour aller plus loin

- Concepts OpenTelemetry : <https://opentelemetry.io/docs/concepts/> · spécification des traces : <https://opentelemetry.io/docs/specs/otel/trace/api/> · W3C Trace Context : <https://www.w3.org/TR/trace-context/>
- Collector, configuration : <https://opentelemetry.io/docs/collector/configuration/> · opérateur : <https://github.com/open-telemetry/opentelemetry-operator>
- Conventions sémantiques : <https://opentelemetry.io/docs/specs/semconv/>
- Tempo 3, configuration : <https://grafana.com/docs/tempo/latest/configuration/> · TraceQL : <https://grafana.com/docs/tempo/latest/traceql/>
- SDK Python : <https://opentelemetry.io/docs/languages/python/> · SDK Go : <https://opentelemetry.io/docs/languages/go/>
