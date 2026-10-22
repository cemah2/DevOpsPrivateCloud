# Comparatif Tempo / Jaeger (M23-E15)

> Document d'exemple du corrigé : les mesures sont celles d'un lab de référence (même trafic envoyé aux deux
> pendant 45 min par la passerelle, après échantillonnage), remplace-les par les tiennes.

| Critère | Tempo 3.1 (monolithique, RGW) | Jaeger 2.22 (all-in-one, mémoire) |
|---|---|---|
| Stockage | Stockage objet (RGW `tempo-k8s-par1`), blocs vParquet5 ; pas de base à exploiter | Mémoire pour l'essai ; en production : OpenSearch/Elasticsearch, Cassandra ou ClickHouse, **à exploiter en plus** |
| Rétention 14 jours | Coût d'objets RGW (≈ 21 Go mesurés, voir capacite-securite.md) | Index OpenSearch de la même taille environ, plus la mémoire et le disque des nœuds OpenSearch (M22-E15 : ≈ 2 Go de mémoire pour un nœud) |
| Requêtes | TraceQL : attributs, durée, statut, **structure** (`>>`, `~`), métriques de traces (`rate()`, `quantile_over_time`) | Recherche par service, opération, étiquettes, durée ; pas de requête structurelle (« span lente **sous** l'appel à MédiDoc » introuvable directement) |
| Retrouver une trace par son identifiant | Oui (Grafana, API) | Oui (interface, API) |
| Graphe de services | Séries `traces_service_graph_*` dans Prometheus (M23-E13), historique long | Graphe de dépendances de l'interface ; en mémoire seulement pendant l'essai |
| Liens avec les autres signaux | Natifs dans Grafana : traces ↔ journaux (Loki), exemplars ↔ métriques, traces → profils (Pyroscope) | Source Grafana « Jaeger » existe, mais sans les liens vers profils et avec moins de réglages ; interface Jaeger séparée |
| Mémoire mesurée | Tempo : 1,1 Gio (avec *metrics-generator*) | Jaeger : 610 Mio pour ≈ 9 000 traces en mémoire (croît jusqu'à `max_traces`) |
| CPU mesuré | 120 m | 60 m |
| Exploitation | Un chart, un compartiment ; compaction et rétention internes | Un binaire simple ; tout le poids est dans le magasin de données choisi |
| Écosystème | Grafana Labs (AGPL), même pile que Loki, Pyroscope, Alloy | CNCF *graduated*, très répandu ; construit sur le Collector OpenTelemetry depuis la v2 ; v1 en fin de vie |

## Recommandation

Garder **Tempo**. Les deux raisons qui décident : le stockage sur le RGW que nous exploitons déjà (Jaeger demanderait OpenSearch ou Cassandra, que nous avons justement écartés au M22 pour les journaux) et TraceQL avec les liens natifs vers Loki, Prometheus et Pyroscope dans Grafana, que les équipes utilisent déjà. Jaeger reste un bon outil, plus simple à démarrer, et l'instrumentation OpenTelemetry nous permet d'en changer sans toucher au code des applications : c'est ce qui rend la décision réversible.

## Décision

Tempo retenu, Jaeger écarté (ADR-0230). L'essai est retiré : Application `jaeger-essai`, espace `jaeger-essai`, exportateur `otlp_grpc/jaeger` de la passerelle. Pendant l'arrêt volontaire de Jaeger (1 min), la passerelle n'a perdu aucune span vers Tempo (`otelcol_exporter_send_failed_spans{exporter="otlp_grpc/tempo"}` resté à 0) ; la file de l'exportateur Jaeger s'est remplie puis vidée.
