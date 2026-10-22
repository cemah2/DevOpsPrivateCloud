# Module 23 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Avec une chaîne de télémétrie, « j'ai redémarré le Collector et ça remarche » est presque toujours faux : la configuration fautive revient avec le pod, et les métriques internes qui prouvaient la cause repartent de zéro.

**Mécanique des pannes** (pour comprendre ce que tu as vu, après coup) : scripts [`pannes/break-E19.sh`](pannes/break-E19.sh) à [`break-E23.sh`](pannes/break-E23.sh) et [`_m23-commun.sh`](pannes/_m23-commun.sh). Les modifications de configuration sont des **commits de Lucas Martin** (`M23-EXX` dans le message) sur `main` des dépôts `plateforme/observabilite`, `mediagenda/deploiement` ou `medidoc/deploiement`, appliqués par Argo CD ; une seule variante (E19-3) pose un objet directement dans le cluster, et la lenteur L1 de M23-E23 modifie la base de dev. `--annuler` fait un **commit inverse** seulement si le fichier porte encore exactement le contenu de la panne.

**Points non testés en conditions réelles** : les scripts de panne ont passé `shellcheck` et `bash -n` ; leurs expressions `yq`, `awk` et `jq` ont été rejouées sur les fichiers des corrigés de M23-E02 à M23-E16 (configurations des Collectors, values de Tempo, sources Grafana, overlays) et le résultat validé (`otelcol-contrib validate`, `tempo -config.verify`, `kustomize build`) ; le témoin de trafic a été essayé contre une fausse API. Le reste (Argo CD, GitLab, Tempo réel, CNPG) est **à vérifier sur ton lab** ; signale tout écart. Les sorties de commandes ci-dessous sont plausibles, tes valeurs différeront.

---

### M23-E19 — Panne : plus aucune trace

**Démarche de diagnostic**

*Symptômes* : aucune trace récente de `mediagenda-api` (dev) dans Tempo ; l'API, ses métriques et ses journaux sont normaux.

*Hypothèses*, par maillon : l'application n'exporte plus (adresse, protocole, échantillonneur) ; l'agent ne reçoit plus (récepteur, pods) ; le réseau refuse (politique Cilium) ; la passerelle n'envoie plus à Tempo (exportateur) ; Tempo refuse (limites) ; Grafana ne lit plus (source).

**Étape 1 — Le maillon muet, par les métriques des Collectors.**

```
# Thanos Query (10.10.41.60)
sum by (job) (rate({__name__=~"otelcol_receiver_accepted_spans(_total)?"}[5m]))
sum by (job, exporter) (rate({__name__=~"otelcol_exporter_sent_spans(_total)?"}[5m]))
sum by (job, exporter) (rate({__name__=~"otelcol_exporter_send_failed_spans(_total)?"}[5m]))
max by (job, exporter) (otelcol_exporter_queue_size / otelcol_exporter_queue_capacity)
```

Puis le périmètre dans Tempo : `{resource.service.name = "medidoc"}`, `{resource.deployment.environment.name = "recette"}`, `{resource.service.name = "adm01-essai"}` (émetteur externe de M23-E16) : une seule application, toute la chaîne, ou seulement ce qui passe par les agents ?

**Variante 1 — L'application exporte vers le mauvais port.**

Seul MédiAgenda de dev a disparu ; les agents acceptent encore les spans de MédiDoc (qui arrivent maintenant **sans parent**, racines dans `medidoc` : un indice de plus). Journal de l'application :

```
admin@adm01:~$ kubectl -n mediagenda-dev logs deploy/mediagenda --since=10m | grep -i -m3 export
{"niveau": "WARNING", "journal": "opentelemetry.exporter.otlp.proto.grpc.exporter", "message": "Transient error StatusCode.UNAVAILABLE encountered while exporting traces to otel-agent-collector.traces.svc.cluster.local:4318, retrying in 1s."}
admin@adm01:~$ kubectl -n mediagenda-dev get deploy mediagenda -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep OTLP
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-agent-collector.traces.svc.cluster.local:4318
```

Le composant `telemetrie` pose 4317 ; un patch de l'overlay `dev`, appliqué après lui, a remplacé la valeur. Le port 4318 de l'agent parle OTLP/**HTTP** ; l'exportateur de MédiAgenda est **gRPC** : la connexion s'établit, la négociation HTTP/2 échoue, et le SDK abandonne les lots après ses reprises. Origine :

```
admin@adm01:~/src/mediagenda-deploiement$ git pull -q && git log -3 --format='%h %an %s' -- overlays/dev/
4c1e9a0 Lucas Martin dev : harmonisation du point d'accès OTLP de l'API
admin@adm01:~/src/mediagenda-deploiement$ git show 4c1e9a0 | tail -12      # un patch JSON 6902 ajouté à overlays/dev/kustomization.yaml
```

Correctif : `git revert 4c1e9a0` par une MR (approuvée), Argo CD synchronise, MédiAgenda redémarre avec la bonne adresse. Prévention : l'adresse et le protocole ne se décident qu'à un endroit, le composant `components/telemetrie` ; un overlay qui redéfinit une variable `OTEL_*` doit être refusé en revue (ou par une règle `kubeconform`/`conftest` dans la CI de `…/deploiement`).

**Variante 2 — La passerelle exporte vers un Tempo qui n'existe pas.**

Toutes les applications et tous les environnements ont disparu, l'émetteur externe aussi. Les agents envoient, la passerelle reçoit ; ses envois vers Tempo échouent et sa file monte :

```
admin@adm01:~$ kubectl -n traces logs deploy/otel-passerelle-collector --since=10m | grep -m2 -i -E 'export|dial'
… error exporterhelper/queue_sender.go … "Exporting failed. Will retry the request after interval." {"otelcol.component.id": "otlp_grpc/tempo", "error": "rpc error: code = Unavailable desc = name resolver error: produced zero addresses" …}
admin@adm01:~$ kubectl -n traces get otelcol otel-passerelle -o jsonpath='{.spec.config.exporters}' | jq
{ "otlp_grpc/tempo": { "endpoint": "tempo-distributor.traces.svc.cluster.local:4317", … } }
admin@adm01:~$ kubectl -n traces get svc tempo-distributor
Error from server (NotFound): services "tempo-distributor" not found
```

`tempo-distributor` est le nom du Service en mode **microservices** (chart `tempo-distributed`) ; en monolithique, c'est `tempo`. Correctif : revert du commit de Lucas dans `plateforme/observabilite` (MR), synchronisation de `otel`. Les spans gardées dans la file pendant moins de `max_elapsed_time` (300 s) partent dès que Tempo est joignable ; les autres sont perdues (`otelcol_exporter_send_failed_spans`). Prévention : un test de bout en bout dans la CI de `plateforme/observabilite` (rendu des CR, `otelcol-contrib validate`, et vérification que chaque `endpoint` vise un Service déclaré dans le dépôt).

**Variante 3 — Une règle Cilium refuse le port 4317 de la passerelle.**

Les agents acceptent, mais leurs envois vers la passerelle échouent ; la passerelle ne reçoit plus rien des agents (l'émetteur externe, qui arrive sur 14317, passe encore) :

```
admin@adm01:~$ hubble observe -n traces --to-port 4317 --verdict DROPPED --last 5
Nov 10 08:02:11.304: traces/otel-agent-collector-x7k2p:41532 (ID:23112) <> traces/otel-passerelle-collector-6d9f…:4317 (ID:30871) Policy denied by denylist DROPPED (TCP Flags: SYN)
admin@adm01:~$ kubectl -n traces get cnp
NAME                         AGE
traces-agent                 12d
traces-exposition-reduite    41m
traces-passerelle            12d
traces-pyroscope             9d
traces-tempo                 12d
admin@adm01:~$ kubectl -n traces get cnp traces-exposition-reduite -o yaml | yq '.metadata.annotations, .metadata.managedFields[0].manager, .spec'
```

Une politique de **refus** (`ingressDeny` depuis `all` vers 4317) l'emporte sur toutes les autorisations ; elle n'est pas dans Git (pas d'annotation de suivi d'Argo CD, gestionnaire de champs `kubectl`), elle porte un ticket `CHG-5019` qui n'existe pas. Correctif : la supprimer (elle n'est pas gérée par Argo CD, rien ne la recréera), retrouver qui l'a posée (journal d'audit de l'API, locataire `audit` du M22, lu dans l'organisation « Sécurité » de Grafana depuis M22-E16 : `{job="kubernetes-audit"} | resource="ciliumnetworkpolicies" | verb="create"`), et le noter. Prévention : les politiques de l'espace `traces` ne viennent que de Git ; une alerte sur les paquets refusés par politique dans les espaces de plateforme (métriques de Hubble `hubble_drop_total{reason="POLICY_DENIED"}`, M21-E20).

**Variante 4 — Le récepteur de l'agent n'accepte plus le gRPC.**

Plus rien de MédiAgenda **ni** de MédiDoc, dans tous les environnements ; l'émetteur externe passe encore (il entre par la passerelle). Les agents n'acceptent plus rien :

```
admin@adm01:~$ kubectl -n traces get otelcol otel-agent -o jsonpath='{.spec.config.receivers.otlp.protocols}' | jq
{ "http": { "endpoint": "0.0.0.0:4318" } }
admin@adm01:~$ kubectl -n mediagenda-dev logs deploy/mediagenda --since=10m | grep -m1 -i export
… "Failed to export traces to otel-agent-collector.traces.svc.cluster.local:4317, error code: StatusCode.UNAVAILABLE" …
admin@adm01:~$ kubectl -n traces get svc otel-agent-collector -o jsonpath='{.spec.ports[*].port}'
4318
```

L'opérateur a retiré le port 4317 du Service quand le protocole a disparu de la configuration ; nos applications exportent en gRPC (4317). « Réduire la surface » sans inventaire des émetteurs a coupé tout le monde. Correctif : revert du commit (MR), synchronisation, vérification du Service (4317 et 4318). Prévention : l'inventaire des protocoles utilisés est dans `conventions-telemetrie.md` ; le check de M23-E19 vérifie les deux protocoles.

**Clôture** : nouvelles traces de `mediagenda-api` et `medidoc` en dev, compteurs d'échec à zéro, `lab/bin/check 23 19`, `lab/bin/break 23 19 --annuler`. Runbook : [`RB-230`](fichiers/M23-E19/medisphere/docs/observabilite/traces/runbooks/RB-230-plus-aucune-trace.md).

**Explications**

Les SDK OpenTelemetry sont conçus pour **ne jamais gêner l'application** : en cas d'échec d'export, ils réessaient un peu, puis abandonnent en silence (un avertissement dans les journaux). C'est voulu (l'observabilité ne doit pas faire tomber le service), mais cela veut dire qu'une chaîne de traces cassée ne se voit que si on la surveille : d'où l'alerte `TracesAbsentes` et les métriques internes des Collectors.

**Pièges classiques**
- Regarder Grafana et Tempo en premier : ils sont au bout de la chaîne, et rarement en cause.
- Redémarrer les Collectors « pour voir » : la configuration revient, les compteurs repartent de zéro.
- Corriger la CNP ou l'endpoint par `kubectl edit` : Argo CD remet la panne (sauf pour la variante 3, hors Git).
- Conclure « Tempo en panne » parce qu'aucune trace n'arrive, sans avoir vu que l'émetteur externe passe encore.

**En production chez MédiSphère**

`TracesAbsentes` par environnement et par service (`absent_over_time` sur les span metrics de chaque service attendu), validation des configurations de Collectors en CI, et une trace synthétique toutes les 5 min (sonde qui émet une trace en erreur, donc toujours gardée, et vérifie qu'elle est trouvable dans Tempo).

---

### M23-E20 — Panne : les traces sont coupées en morceaux

**Démarche de diagnostic**

*Symptômes* : spans client de MédiAgenda vers MédiDoc sans suite, traces dont la racine est dans MédiDoc, arête du graphe de services instable.

*Hypothèses* : propagation (le contexte ne passe pas), échantillonnage en tête incohérent (MédiDoc décide seul), échantillonnage en queue sans équilibrage (la trace est jugée en morceaux).

**Étape 1 — Mesurer avec TraceQL** (dernière demi-heure) :

```
{resource.service.name = "mediagenda-api"} >> {resource.service.name = "medidoc"}                    # traces entières
{trace:rootService = "medidoc" && resource.deployment.environment.name = "dev"}                     # morceaux MédiDoc
{resource.service.name = "mediagenda-api" && kind = client && span.server.address =~ "medidoc.*"}   # appels émis
```

Ouvre un morceau : sa span racine (`POST /documents` de MédiDoc) a-t-elle un `parentSpanId` ?

**Étape 2 — Les variables des deux services.**

```
admin@adm01:~$ for ns in mediagenda-dev medidoc-dev; do echo "== $ns"; kubectl -n $ns get deploy -o jsonpath='{range .items[*].spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep -E 'OTEL_(PROPAGATORS|TRACES_SAMPLER)'; done
```

**Variante 1 — Le propagateur de MédiAgenda n'injecte plus `traceparent`.**

```
== mediagenda-dev
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_PROPAGATORS=baggage
```

Racines dans MédiDoc **sans** `parentSpanId` : MédiDoc n'a reçu aucun contexte. Avec `OTEL_PROPAGATORS=baggage`, le SDK de MédiAgenda n'injecte que l'en-tête `baggage` ; l'instrumentation du client HTTP n'ajoute pas `traceparent`. Preuve directe côté réseau (Hubble en L7 si activé sur ce port, ou un journal de MédiDoc en DEBUG qui affiche les en-têtes reçus). Origine : commit de Lucas dans `mediagenda/deploiement` (overlay dev, « propagation allégée »). Correctif : revert ; `tracecontext,baggage` est déjà la valeur du composant `telemetrie`. Prévention : variables `OTEL_*` dans le seul composant, jamais dans un overlay.

**Variante 2 — MédiDoc échantillonne sans tenir compte de son parent.**

```
== medidoc-dev
OTEL_TRACES_SAMPLER=traceidratio
OTEL_TRACES_SAMPLER_ARG=0.2
```

Environ 80 % des traces de MédiAgenda n'ont plus de partie MédiDoc ; les 20 % restants sont entières (même identifiant de trace, même décision par hachage pour toutes les spans MédiDoc de la trace). `traceidratio` seul ignore le drapeau *sampled* du `traceparent` reçu ; `parentbased_traceidratio` suit la décision du parent et n'applique le ratio qu'aux racines. Origine : commit dans `medidoc/deploiement`. Correctif : revert (`parentbased_traceidratio`, ratio 1.0 en dev). Prévention : un seul échantillonneur pour toute l'entreprise (`parentbased_*`), écrit dans `conventions-telemetrie.md`.

**Variante 3 — Les agents n'équilibrent plus par `traceID`.**

Les variables sont saines ; les morceaux de MédiDoc ont un `parentSpanId`, mais ce parent n'existe pas dans Tempo, ou l'inverse (la span client est là, l'enfant manque). Configuration de l'agent :

```
admin@adm01:~$ kubectl -n traces get otelcol otel-agent -o jsonpath='{.spec.config.service.pipelines.traces.exporters}{"\n"}'
["otlp_grpc/passerelle"]
admin@adm01:~$ kubectl -n traces get otelcol otel-agent -o jsonpath='{.spec.config.exporters.otlp_grpc/passerelle.endpoint}{"\n"}'
otel-passerelle-collector.traces.svc.cluster.local:4317
admin@adm01:~$ kubectl get pods -A -o wide -l 'app.kubernetes.io/name in (mediagenda,medidoc)' | awk '{print $1, $2, $8}'
```

Le Service ClusterIP répartit **par connexion** : l'agent d'un nœud parle à un réplica, celui d'un autre nœud peut parler à l'autre. MédiAgenda et MédiDoc tournent sur des nœuds différents : leurs spans d'une même trace arrivent sur deux réplicas, qui décident chacun sur une trace partielle (une moitié peut être gardée, l'autre jetée). Métriques par réplica : `otelcol_processor_tail_sampling_*` (décisions) très différentes d'un réplica à l'autre. Origine : commit « envoi simplifié » dans `plateforme/observabilite`. Correctif : revert (exportateur `loadbalancing` à clé `traceID`, résolveur `k8s` sur le Service sans tête). Prévention : le check de M23-E20 et un commentaire dans `otel-agent.yaml` qui explique pourquoi.

**Clôture** : traces entières sur 15 min, aucune racine dans MédiDoc, arête stable ; `lab/bin/check 23 20`, `--annuler`. Runbook : [`RB-231`](fichiers/M23-E20/medisphere/docs/observabilite/traces/runbooks/RB-231-traces-coupees.md).

**Explications**

Une trace n'est qu'une convention : des spans qui partagent un `trace_id` et pointent vers leur parent. Trois mécanismes doivent tenir ensemble : la **propagation** (le contexte passe d'un processus à l'autre), la **décision d'échantillonnage** (prise une fois, à la racine, et suivie par les enfants grâce au drapeau *sampled*), et, avec un échantillonnage en queue, le **regroupement** de toutes les spans d'une trace au même endroit avant la décision.

**Pièges classiques**
- Chercher dans le code des applications (« rien n'a changé ») alors que la cause est dans l'environnement (variables, Collectors).
- Mettre `OTEL_PROPAGATORS=b3` sur un service Python sans le paquet correspondant : le SDK refuse de démarrer (propagateur introuvable) ; une autre panne.
- Corriger la variante 3 en passant la passerelle à un réplica : ça marche, mais on perd la haute disponibilité.

**En production chez MédiSphère**

Test de propagation dans la CI de chaque application (requête de bout en bout, `traceparent` vérifié côté appelé, comme `test_traceparent_transmis_a_medidoc` de M23-E06) ; alerte sur la part de traces enracinées dans un service qui n'est appelé que par d'autres.

---

### M23-E21 — Panne : le Collector perd des données

**Démarche de diagnostic**

*Symptômes* : moins de traces, des traces d'erreurs introuvables, tableau « Pipeline de traces » avec un trou entre ce qui entre et ce qui sort.

*Hypothèses* : refus à l'entrée (mémoire), file pleine (destination lente), envoi refusé par Tempo (limites), lots trop gros.

**Étape 1 — Le bilan entrée/sortie par Collector** (requêtes de [RB-232](fichiers/M23-E21/medisphere/docs/observabilite/traces/runbooks/RB-232-collector-perd-des-donnees.md)) ; **étape 2** — le message exact dans les journaux de la passerelle et de Tempo ; **étape 3** — la configuration vivante et l'historique Git.

**Variante 1 — `memory_limiter` trop bas.**

```
sum by (job) (rate({__name__=~"otelcol_processor_memory_limiter_refused_spans(_total)?"}[5m]))     # > 0 sur la passerelle
otelcol_process_runtime_heap_alloc_bytes{job=~".*otel-passerelle.*"}                                # ~ 30 Mio, loin de la limite de 1 Gio du conteneur
admin@adm01:~$ kubectl -n traces logs deploy/otel-passerelle-collector --since=5m | grep -m1 -i refused
… "Memory usage is above soft limit. Refusing data." {"otelcol.component.id": "memory_limiter", "cur_mem_mib": 31} …
admin@adm01:~$ kubectl -n traces get otelcol otel-passerelle -o jsonpath='{.spec.config.processors.memory_limiter}'
{"check_interval":"1s","limit_mib":32,"spike_limit_mib":8}
```

Limite douce = 32 − 8 = 24 Mio : en dessous de la consommation **normale** de la passerelle (échantillonnage en queue compris). Elle refuse tout, les agents réessaient puis abandonnent (`otelcol_exporter_send_failed_spans` côté agents). Correctif : revert (`limit_percentage: 80`, `spike_limit_percentage: 20`, relatifs à la limite du conteneur). Prévention : des valeurs relatives plutôt qu'absolues, et l'alerte `CollectorRefuseDesSpans`.

**Variante 2 — File minuscule et Tempo lent.**

```
max by (job, exporter) (otelcol_exporter_queue_size / otelcol_exporter_queue_capacity)     # 1 (5/5) sur otlp_grpc/tempo
sum by (job, exporter) (rate({__name__=~"otelcol_exporter_enqueue_failed_spans(_total)?"}[5m]))   # > 0
histogram_quantile(0.99, sum by (le) (rate(tempo_request_duration_seconds_bucket{route=~".*Push.*|.*Export.*"}[5m])))  # ~ 2 s
admin@adm01:~$ kubectl -n traces logs deploy/otel-passerelle-collector --since=5m | grep -m1 -i 'queue is full'
… "Dropping data because sending_queue is full. Try increasing queue_size." {"otelcol.component.id": "otlp_grpc/tempo", "dropped_items": 812} …
```

Deux réglages du même commit : la file de l'exportateur Tempo réduite à 5 requêtes avec un seul consommateur, et `overrides.defaults.ingestion.artificial_delay: 2s` dans Tempo (qui fait durer chaque réception au moins 2 s). Débit maximal : une requête toutes les 2 s ; tout le reste déborde. Correctif : revert des deux fichiers. Prévention : `artificial_delay` n'a rien à faire en production (c'est un réglage de test) ; files dimensionnées en `items`.

**Variante 3 — Lots plus gros que la rafale permise par Tempo.**

```
sum by (job, exporter) (rate({__name__=~"otelcol_exporter_send_failed_spans(_total)?"}[5m]))   # > 0 après quelques minutes
sum by (reason) (rate(tempo_discarded_spans_total[5m]))                                       # reason="rate_limited"
admin@adm01:~$ kubectl -n traces logs deploy/otel-passerelle-collector --since=10m | grep -m1 RATE_LIMITED
… "RATE_LIMITED: ingestion rate limit (local: 15000000 bytes, burst: 60000 bytes) exceeded while adding 412887 bytes for user single-tenant" …
admin@adm01:~$ kubectl -n traces get otelcol otel-passerelle -o jsonpath='{.spec.config.processors.batch}'
{"send_batch_max_size":0,"send_batch_size":20000,"timeout":"30s"}
```

Le seau à jetons de Tempo fait 60 000 octets ; un lot de 30 s pèse 400 Ko : il ne passera **jamais**, quel que soit le débit moyen. La passerelle réessaie pendant `max_elapsed_time` puis abandonne ; pendant ce temps, la file se remplit. Correctif : revert (lots bornés à 2 048 spans, rafale de 20 Mo). Prévention : la règle « lot max < rafale » écrite dans `capacite-securite.md`, et le check de M23-E21.

**Clôture** : 15 min sans refus ni perte, files sous 50 % ; alertes de `regles/traces-collectors.yaml` vérifiées (elles auraient sonné en 10 min : `CollectorRefuseDesSpans` pour la variante 1, `CollectorPerdDesSpans` et `CollectorFileDAttentePleine` pour les autres) ; `lab/bin/check 23 21`, `--annuler`.

**Explications**

Dans un Collector, une span peut se perdre à trois endroits : à l'entrée (refus du `memory_limiter`, que l'émetteur peut réessayer), à la mise en file de l'exportateur (file pleine : perdue tout de suite, `enqueue_failed`), à l'envoi (après les reprises, `send_failed`). Chaque endroit a son compteur ; leur somme, comparée aux spans acceptées, est le taux de perte. Les erreurs `RATE_LIMITED` de Tempo sont retentables (avec un délai conseillé), mais une requête plus grosse que la rafale échouera à chaque reprise.

**Pièges classiques**
- Augmenter la mémoire de la passerelle pour la variante 1 : le `memory_limiter` en valeurs absolues continue de refuser.
- Agrandir indéfiniment la file pour la variante 2 : on déplace le problème vers un OOM.
- Relever `rate_limit_bytes` pour la variante 3 : c'est la rafale (`burst_size_bytes`) et la taille des lots qui comptent.
- Chercher la perte dans Tempo alors que la span n'a jamais quitté la passerelle.

**En production chez MédiSphère**

Tableau « Pipeline de traces » (entrées, sorties, refus, files, par Collector) dans `tableaux/`, alertes de M23-E16 routées vers `plateforme-mail`, et toute modification des réglages de débit passe par un essai de charge (M29).

---

### M23-E22 — Panne : impossible de passer d'une trace à ses journaux

**Démarche de diagnostic**

*Symptômes* : « Logs for this span » ouvre une erreur ou une requête vide ; le bouton « Voir la trace » a disparu de certaines lignes de journal.

**Étape 1 — Ce que Grafana sert vraiment** :

```
admin@adm01:~$ G() { curl -s -K <(printf 'header = "Authorization: Bearer %s"\n' "$(<~/.config/workbook/grafana-checks.token)") "https://grafana.apps.par1.medisphere.internal/api/$1"; }
admin@adm01:~$ G frontend/settings | jq '.datasources[] | select(.type == "tempo") | .jsonData.tracesToLogsV2'
admin@adm01:~$ G frontend/settings | jq '.datasources[] | select(.type == "loki") | {name, uid, champs: .jsonData.derivedFields}'
admin@adm01:~/src/observabilite$ git log -3 --format='%h %an %s' -- grafana/
```

**Variante 1 — Champ dérivé sur le mauvais nom.**

`Loki — mediagenda` : `derivedFields[0].matcherRegex: traceid` ; les journaux portent `trace_id` (métadonnée structurée, M23-E08). `matcherType: label` cherche une étiquette **nommée** `traceid` : aucune ligne n'en a, le lien disparaît. Origine : commit « champ dérivé aligné sur la convention OpenTelemetry » (Lucas a confondu `traceId` du format OTLP JSON et le nom de notre champ). Correctif : revert ; `trace_id` partout (journaux, métadonnées structurées, exemplars, sources).

**Variante 2 — Lien vers une source qui n'existe pas.**

`tracesToLogsV2.datasourceUid: loki-mediagenda-ancien` ; aucune source n'a cet UID : Grafana affiche une erreur de source introuvable (ou n'affiche pas le lien). Correctif : revert (`loki-mediagenda`).

**Variante 3 — Lien vers le mauvais locataire.**

`tracesToLogsV2.datasourceUid: loki-plateforme` : le lien ouvre une requête valide (`{namespace="mediagenda-dev"} | trace_id="…"`) dans la source du locataire `plateforme`, qui n'a pas les journaux de MédiAgenda (ils sont chez `mediagenda`, M22) : résultat vide, sans erreur. Correctif : revert. C'est la plus traîtresse : le lien « marche ».

**Clôture** : dans les deux sens depuis une trace de MédiAgenda de dev ; `lab/bin/check 23 22`, `--annuler`. Le *sidecar* recharge les sources provisionnées en une minute environ ; si rien ne change, redémarre Grafana (`kubectl -n supervision rollout restart deploy/<grafana>`). Runbook : [`RB-233`](fichiers/M23-E22/medisphere/docs/observabilite/traces/runbooks/RB-233-lien-trace-journaux.md).

**Explications**

Un lien de Grafana entre signaux n'est qu'une **requête préparée** dans une autre source : il faut la bonne source (donc le bon locataire, porté par l'en-tête `X-Scope-OrgID` de la source), le bon champ, et une fenêtre de temps qui contient les journaux. Les sources étant provisionnées, une correction dans l'interface est refusée (source non modifiable) ou écrasée au prochain chargement.

**Pièges classiques**
- Corriger dans l'interface de Grafana : refusé (`editable: false`) ou défait.
- Conclure que « les journaux n'ont pas de `trace_id` » sans regarder le locataire interrogé.
- Ajouter le locataire `mediagenda` à la source `Loki — plateforme` « pour que ça marche » : on casse le cloisonnement des données (M22-E16).

**En production chez MédiSphère**

Un test des sources dans la CI de `plateforme/observabilite` (chaque `datasourceUid` référencé existe dans le dépôt ; chaque champ dérivé vise un champ réellement présent dans les journaux d'exemple).

---

### M23-E23 — Astreinte : l'API est lente

**Démarche de diagnostic**

L'injection combine une panne de M23-E19 à E22 (voir plus haut, variante tirée au hasard) et une **lenteur** de MédiAgenda en dev, posée **d'abord** :

| Lenteur | Mécanisme | Ce que montrent les signaux |
|---|---|---|
| **L1** — déclencheur `controle_coherence_rdv` | fonction PL/pgSQL `PERFORM pg_sleep(0.8)` sur `BEFORE INSERT` de `rendez_vous`, posée par `psql` dans le pod primaire de `mediagenda-db` (commentaire `CHG-5023`) | métriques : seule `POST /api/v1/rendez-vous` ralentit (p95 ~ 0,85 s) ; journaux : `duree_ms` > 800 sur cette route ; trace : span `INSERT mediagenda` de 0,8 s ; profil CPU : **rien** (attente) ; base : `pg_stat_activity` montre `pg_sleep`, `\dS+ rendez_vous` montre le déclencheur |
| **L2** — limite CPU de l'API à 60m | commit de Lucas dans `mediagenda/deploiement` (overlay dev, « ressources alignées sur le quota d'équipe »), patch JSON 6902 `resources.limits.cpu: 60m`, `requests.cpu: 50m` | métriques : **toutes** les routes ralentissent ; `container_cpu_cfs_throttled_periods_total` / `container_cpu_cfs_periods_total` > 50 % ; traces : toutes les spans de l'API s'allongent, y compris le temps propre du gestionnaire, pas les spans de base ; profil CPU : répartition **normale** (le processus est simplement bridé) |

*Ordre de travail* : (1) délimiter par métriques et journaux, qui ne dépendent pas de la chaîne de traces ; (2) rétablir l'observabilité défaillante (runbook de la panne tirée) ; (3) confirmer la cause de la lenteur par la trace (L1 : span de base ; L2 : tout s'allonge) et la base ou les métriques de conteneur ; (4) corriger.

**Requêtes clés**

```
# Quelle route, depuis quand ?
histogram_quantile(0.95, sum by (le, route, methode) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-dev"}[5m])))
# Étranglement CPU ?
sum(rate(container_cpu_cfs_throttled_periods_total{namespace="mediagenda-dev", container="api"}[5m]))
  / sum(rate(container_cpu_cfs_periods_total{namespace="mediagenda-dev", container="api"}[5m]))
```

```
# Journaux (locataire mediagenda)
{namespace="mediagenda-dev", container="api"} | json | duree_ms > 500 | line_format "{{.methode}} {{.route}} {{.duree_ms}}"
```

```
# Traces (une fois la chaîne rétablie)
{resource.service.name = "mediagenda-api" && resource.deployment.environment.name = "dev" && span.db.system.name != nil && duration > 500ms}
{resource.service.name = "mediagenda-api" && kind = server && duration > 300ms} | select(span.http.route)
```

```
# L1 : dans la base (lecture)
admin@adm01:~$ kubectl -n mediagenda-dev exec -it mediagenda-db-1 -c postgres -- psql -d mediagenda -c "\dS+ rendez_vous" | sed -n '/Triggers/,$p'
Triggers:
    controle_coherence_rdv BEFORE INSERT ON rendez_vous FOR EACH ROW EXECUTE FUNCTION controle_coherence_rdv()
admin@adm01:~$ kubectl -n mediagenda-dev exec -it mediagenda-db-1 -c postgres -- psql -d mediagenda -c "SELECT obj_description('controle_coherence_rdv'::regproc, 'pg_proc')"
 Contrôle de cohérence des créneaux (CHG-5023)
```

*Correctifs* : L1 — avec l'accord de Julien (c'est leur base), `DROP TRIGGER controle_coherence_rdv ON rendez_vous; DROP FUNCTION controle_coherence_rdv();` (aucune donnée touchée) ; à la racine, aucune modification de schéma hors migrations (V1, V2… de MédiAgenda) et retrait de l'accès superutilisateur des comptes d'équipe. L2 — revert du commit dans `mediagenda/deploiement` (MR), ou une limite réaliste justifiée par une mesure (le profil de M23-E14 donne la consommation réelle).

**Clôture** : p95 sous 300 ms, plus d'étranglement, plus de span de base au-delà de 500 ms ; les checks de M23-E19 à E22 verts ; `lab/bin/break 23 23 --annuler` (retire ce qui porterait encore la marque des pannes) ; post-mortem publié. Exemple : [`2026-11-10-INC-5023-api-lente.md`](fichiers/M23-E23/medisphere/docs/kubernetes/post-mortems/2026-11-10-INC-5023-api-lente.md).

**Explications**

Chaque signal répond à une question différente : la **métrique** dit *quoi* et *depuis quand* (quelle route, quel percentile) ; le **journal** dit *quelles requêtes* (avec leurs champs) ; la **trace** dit *où* dans la requête (quelle span) ; le **profil** dit *quel code* consomme le CPU. Une lenteur d'attente (L1) est invisible au profil CPU ; une lenteur de bridage (L2) est invisible à la trace « par span » (tout s'allonge proportionnellement) mais évidente dans les métriques du conteneur. Une astreinte qui ne sait lire qu'un signal se trompe une fois sur deux.

**Pièges classiques**
- Attendre que les traces reviennent pour commencer à chercher : les métriques par route et les journaux délimitent en dix minutes.
- Corriger la lenteur et oublier la panne d'observabilité (ou l'inverse) : le check rejoue les deux.
- Supprimer des rendez-vous ou recréer la base « pour repartir propre » : aucune des deux causes ne le demande, et c'est une perte de données.
- Un post-mortem qui accuse Lucas : les causes sont un accès trop large à la base et une revue qui n'a pas vu le changement.

**En production chez MédiSphère**

Alerte de latence par route (avertissement) en plus du SLO, étranglement CPU surveillé par conteneur, aucune modification de schéma hors migrations, et le parcours « métrique → journal → trace → profil » répété en exercice d'astreinte (F3).

---

### M23-E24 — Sous le capot : spans, contexte et OTLP

**Solution**

*Préparation sur `adm01`* (dans `~/m23/e24/`, binaires vérifiés par empreinte comme d'habitude) : `otelcol-contrib` 0.161 (archive des versions du Collector, ou extrait de l'image du cache Harbor par `skopeo copy` puis `tar`), `tempo-cli` 3.1.1 (extrait de l'image `grafana/tempo-cli:3.1.1`, dont c'est le point d'entrée `/tempo-cli`). Puis :

```
admin@adm01:~/m23/e24$ cp ~/DevOpsPrivateCloud/modules/23-traces/ressources/E24-capot/* .
admin@adm01:~/m23/e24$ ./otelcol-contrib --config collecteur-local.yaml > collecteur.log 2>&1 &
admin@adm01:~/m23/e24$ uv run --with opentelemetry-sdk==1.45.1 --with opentelemetry-exporter-otlp-proto-http==1.45.1 python emettre.py
en-têtes injectés par le client : {'traceparent': '00-aa45eabe74b3b8489c204ba341c2953a-cc60fb210cd0a832-03'}
en-têtes reçus par le serveur : {'Traceparent': '00-aa45eabe74b3b8489c204ba341c2953a-cc60fb210cd0a832-03'}
trace_id=aa45eabe74b3b8489c204ba341c2953a span_id(racine)=5e4230c82c3ce166 drapeaux=03
admin@adm01:~/m23/e24$ grep -a -E 'Trace ID|Parent ID|^ +ID|Name +:|Kind +:' collecteur.log | sed 's/^ *//'
Trace ID       : aa45eabe74b3b8489c204ba341c2953a
Parent ID      : 5e4230c82c3ce166
ID             : cc60fb210cd0a832
Name           : GET
Kind           : Client
…
Trace ID       : aa45eabe74b3b8489c204ba341c2953a
Parent ID      : cc60fb210cd0a832
ID             : 188f1eb231e5b26f
Name           : GET /capot
Kind           : Server
admin@adm01:~/m23/e24$ jq -c '.resourceSpans[] | {svc: (.resource.attributes[] | select(.key == "service.name") | .value.stringValue),
    spans: [.scopeSpans[].spans[] | {traceId, spanId, parentSpanId, name, kind}]}' otlp-recu.json
```

(Ces sorties sont celles obtenues en préparant le corrigé.) Le `parent-id` du `traceparent` est l'identifiant de la span **client** `GET`, qui devient le parent de la span serveur `GET /capot` ; la racine `traitement` n'a pas de parent. Drapeaux `03` : *sampled* (bit 0) **et** *random* (bit 1, Trace Context niveau 2, posé par les SDK récents parce que leurs identifiants sont aléatoires) ; un ancien SDK enverrait `01`.

*Comparaison des encodages* : l'exportateur OTLP/gRPC (`opentelemetry-exporter-otlp-proto-grpc`, point d'accès `127.0.0.1:24317`) envoie le même protobuf, encadré par HTTP/2 et gRPC ; en JSON (fichier), les identifiants sont en **hexadécimal** (règle propre à OTLP/JSON), là où un protobuf converti « normalement » en JSON les mettrait en base64. Taille : `otelcol_receiver_accepted_spans` ne donne pas les octets ; `tcpdump -i lo -w capot.pcap port 24318` puis `capinfos`/`tshark` les donne (quelques centaines d'octets pour trois spans, la ressource étant envoyée une fois par lot et par service).

*Le chemin d'une span réelle et ses délais* : requête au témoin ou à la main sur MédiAgenda de dev, en notant l'heure ; le SDK l'envoie au plus tard après `OTEL_BSP_SCHEDULE_DELAY` (5 s par défaut), l'agent après `batch.timeout` (2 s), la passerelle attend `decision_wait` (10 s) puis son `batch.timeout` (5 s) : la trace est trouvable par identifiant dans Tempo (*live-store*) après 15 à 25 s ; elle est dans un bloc du compartiment après la fermeture du bloc du *live-store* (`max_block_duration`, puis écriture), visible par `aws s3 ls` et `tempo-cli list blocks` quelques minutes plus tard.

*Le bloc* : `tempo-cli-local.sh` copie le bloc le plus récent avec l'identité de **lecture** (`s3-tempo.env`), puis :

```
admin@adm01:~/m23/e24$ ./tempo-cli-local.sh
admin@adm01:~/m23/e24$ tempo-cli view schema single-tenant <ID-DE-BLOC> --backend local --bucket ~/m23/e24/copie | head -40
admin@adm01:~/m23/e24$ tempo-cli list column single-tenant <ID-DE-BLOC> TraceIDText --backend local --bucket ~/m23/e24/copie | head
admin@adm01:~/m23/e24$ tempo-cli query trace-summary <TRACE-ID> single-tenant --backend local --bucket ~/m23/e24/copie
Number of blocks: 1
Span count: 9
…
Root service name: mediagenda-api
```

Livrable d'exemple : [`sous-le-capot.md`](fichiers/M23-E24/medisphere/docs/observabilite/traces/sous-le-capot.md).

**Explications**

- **W3C Trace Context** : `traceparent` porte l'identité de la trace et du parent immédiat ; c'est tout ce qu'un service a besoin de savoir pour se rattacher. `tracestate` porte des données de fournisseurs, `baggage` des données applicatives (qui traversent **tous** les services : jamais de donnée de santé).
- **OTLP** : un lot regroupe les spans par ressource puis par portée ; les spans ne connaissent que leur parent, l'arbre est reconstruit à la lecture.
- **Bloc vParquet5** : une ligne Parquet par **trace**, colonnes imbriquées (ressources, portées, spans), colonnes dédiées pour les attributs fréquents, statistiques au niveau de la trace (`ServiceStats`, `RootServiceName`) ; `bloom-0` et `index` permettent de ne pas lire `data.parquet` pour une recherche par identifiant, et `meta.json` dit ce que contient le bloc (période, nombre de traces, format) pour ne même pas ouvrir les blocs hors période.

**Pièges classiques**
- Lire un `dict` d'en-têtes HTTP sans normaliser la casse : `Traceparent` n'est pas `traceparent` pour le lecteur par défaut, le serveur ouvre une nouvelle trace (le script fourni montre la correction).
- Lancer `tempo-cli` avec l'identité d'écriture de Tempo, ou pointer `--backend s3` sur le compartiment avec une commande qui écrit (`migrate`, `parquet convert`) : on travaille sur une **copie** locale.
- Confondre le `traceId` du JSON OTLP (hexadécimal) et la colonne `TraceID` binaire du bloc (`TraceIDText` est la version texte).

**En production chez MédiSphère**

Ce document sert d'accueil aux nouveaux de l'équipe et aux développeurs qui instrumentent ; il est relu à chaque montée de version de Tempo (format de bloc) et du SDK (drapeaux, conventions).
