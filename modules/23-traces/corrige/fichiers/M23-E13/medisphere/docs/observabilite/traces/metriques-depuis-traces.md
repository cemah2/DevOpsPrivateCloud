# Métriques tirées des traces (M23-E13)

> Document d'exemple du corrigé : les chiffres sont ceux d'un lab de référence, remplace-les par tes mesures.

## Ce qui est en place

- Tempo 3.1 (monolithique) : *metrics-generator* activé, processeurs `service-graphs` et `span-metrics` (`overrides.defaults.metrics_generator.processors`), dimension supplémentaire `deployment.environment.name` (étiquette `deployment_environment_name`).
- Écriture distante vers **chacun** des deux réplicas de Prometheus (`prometheus-kps-prometheus-0` et `-1` par le Service sans tête `prometheus-operated`), exemplars compris (`send_exemplars: true`).
- Pourquoi pas le Service `kps-prometheus` : il répartit les requêtes entre les deux réplicas. Chaque échantillon n'arriverait que sur l'un des deux ; chaque réplica aurait une série trouée, et Thanos Query, qui déduplique en choisissant un réplica par plage de temps, montrerait des trous ou des marches selon le réplica retenu. Écrire sur les deux coûte deux fois le réseau, pas plus.
- Récepteur d'écriture distante de Prometheus (`enableRemoteWriteReceiver`) : quiconque joint le port 9090 d'un pod Prometheus peut écrire des séries. La CiliumNetworkPolicy `prometheus-ecriture-tempo` n'autorise que Tempo, et seulement `POST /api/v1/write`.

## Séries produites

| Série | Contenu | Étiquettes utiles |
|---|---|---|
| `traces_spanmetrics_calls_total` | nombre de spans | `service`, `span_name`, `span_kind`, `status_code`, `deployment_environment_name` |
| `traces_spanmetrics_latency_bucket` / `_sum` / `_count` | durée des spans | idem + `le` |
| `traces_service_graph_request_total` | requêtes entre deux nœuds | `client`, `server`, `connection_type` |
| `traces_service_graph_request_failed_total` | requêtes en échec | idem |
| `traces_service_graph_request_server_seconds_bucket` / `_client_seconds_bucket` | durée vue de chaque côté | idem + `le` |

Nœuds qui ne sont pas des services instrumentés : la base (`mediagenda`, nœud « virtuel » nommé d'après `db.name`/`db.namespace`), Valkey (`redis`), le stockage S3 de MédiDoc ; et `user` côté client pour les requêtes qui arrivent de l'extérieur.

Cardinalité mesurée après 2 h de trafic : `count({__name__=~"traces_spanmetrics.*"})` = 1 840 séries, `count({__name__=~"traces_service_graph.*"})` = 310 séries. Limite posée : `max_active_series: 20000` (par instance du *metrics-generator*) ; quand elle est atteinte, les nouvelles séries sont ignorées et `tempo_metrics_generator_registry_series_limited_total` augmente (règle d'alerte à ajouter si l'on s'en approche). Le premier facteur de cardinalité est `span_name` : une span nommée avec un identifiant (`GET /api/v1/rendez-vous/4182`) créerait une série par rendez-vous. L'instrumentation FastAPI et `otelhttp` nomment les spans d'après la **route** : à vérifier pour toute span ajoutée à la main.

## Écart avec les métriques applicatives (recette, 15 min de charge à 20 req/s)

| Indicateur | Métriques applicatives (`mediagenda_http_requests_total`, `mediagenda_http_request_duration_seconds`) | Span metrics (`traces_spanmetrics_*`) | Pourquoi |
|---|---|---|---|
| Débit (routes `/api/…`) | 20,1 req/s | 2,4 spans serveur/s | Échantillonnage en queue : 10 % des traces « normales » ; les erreurs et les lentes à 100 % s'ajoutent |
| Taux d'erreurs 5xx | 0,4 % | 3,3 % | Les erreurs sont gardées à 100 %, le dénominateur à ~10 % : le ratio est gonflé d'un facteur ~8 |
| Latence p95 | 180 ms | 520 ms | Les traces lentes (> 500 ms) sont toutes gardées : la distribution est déformée vers le haut |

Conclusion : des métriques calculées sur des traces **échantillonnées** ne sont pas des métriques de trafic. Elles servent à :
- dessiner le **graphe de services** (qui appelle qui, avec quelle latence relative) ;
- donner un RED aux composants **sans** métriques propres (appels sortants, dépendances) ;
- porter des **exemplars** vers des traces réelles.

Elles ne servent **pas** aux SLO (Pyrra, M21-E26), à la facturation, ni aux alertes de débit : ces usages restent sur `mediagenda_http_*` et `medidoc_http_*`. Les règles d'enregistrement `service:traces_spanmetrics_*` (fichier `regles/traces-red.yaml`) portent un nom distinct pour qu'on ne les confonde pas.

Pour des span metrics exactes, il faudrait les calculer **avant** l'échantillonnage en queue (connecteur `spanmetrics` dans un pipeline de la passerelle), au prix de séries et de mémoire en plus dans la passerelle : non retenu pour l'instant (ADR-0230).
