# Performance et cardinalité de Loki

> Exemple de livrable de M22-E14. Les chiffres sont **ceux d'un lab de référence** (socle v4, `k8s-par1`, trafic d'essai de MédiAgenda) : remplace-les par tes mesures, la méthode compte plus que les valeurs.

| | |
|---|---|
| Mesuré le | 2026-10-29, 10 h - 11 h (heure de Paris) |
| Loki | 3.7.9, mode Monolithic, 1 pod (`loki-0`, limite mémoire 2 Gio) |
| Outils | `logcli` 3.7 (`series --analyze-labels`, `query --stats`), `/metrics` de Loki, Prometheus |

## 1. Cardinalité par locataire

| Locataire | Flux actifs (`loki_ingester_memory_streams`) | Flux sur 24 h (`logcli series`) | Étiquettes (valeurs) | Limite E13 | **Seuil d'alerte** (50 %) |
|---|---|---|---|---|---|
| `plateforme` | 412 | 655 | `namespace` (38), `container` (71), `app` (52), `node` (6), `job` (3), `host` (12), `role` (8), `site` (1), `cluster` (1) | 10 000 | 5 000 |
| `mediagenda` | 24 | 31 | `namespace` (3), `container` (4), `app` (3), `node` (3), `job` (1), `cluster` (1) | 2 000 | 1 000 |
| `medidoc` | 6 | 8 | idem | 2 000 | 1 000 |
| `audit` | 4 | 5 | `job` (2), `node` (3), `cluster` (1) | 500 | 250 |
| `essai` | 0 à 3 | 3 | `job`, `namespace` | 500 | 250 |

- L'étiquette qui a le plus de valeurs est `container` dans `plateforme` : elle suit le nombre de composants (bornée).
- Le flux « le plus gros » est `{namespace="kube-system", container="cilium-agent"}` (≈ 30 % des octets de `plateforme`).
- `service_name` : coupée depuis E02 (`discover_service_name: []`) pour respecter la liste fermée ; aucune trace sur 1 h ; sur 7 jours, quelques flux écrits avant la coupure, qui disparaîtront avec la rétention. Logs Drilldown de Grafana regroupe alors sur `unknown_service`, ce que l'équipe accepte (les tableaux utilisent `namespace` et `app`). Si on la réactive un jour, c'est une étiquette dérivée de `app`/`container`, donc de cardinalité bornée : à décider par MR.
- `__stream_shard__` n'apparaît pas (aucun flux ne dépasse 1,5 Mo/s) ; elle est tolérée si elle apparaît.

## 2. Chunks

| Mesure | Valeur | Lecture |
|---|---|---|
| Taille médiane des chunks vidés | 180 Kio (cible 1,5 Mio) | Flux peu bavards : les chunks partent sur **inactivité** (30 min) ou **âge** (2 h), pas sur taille |
| Raisons de vidage (`loki_ingester_chunks_flushed_total`) | `idle` 61 %, `max_age` 33 %, `full` 6 % | Normal pour un lab ; en production, viser plus de `full` |
| Compression (snappy) | 5,8 | Journaux JSON répétitifs |
| Une étiquette `pod` ajoutée | ×4 à ×10 flux dans `mediagenda` (chaque redémarrage = nouveau flux), chunks 4 à 10 fois plus petits, index plus gros, mémoire de l'ingester en hausse | Interdit (liste fermée) : le pod est une métadonnée structurée |

## 3. Requêtes (locataire `plateforme`, 7 jours)

| Requête | Avant (octets traités / chunks / temps) | Après réglages (1re / 2e exécution) |
|---|---|---|
| `{namespace="mediagenda-recette"}` (limite 1 000 lignes) | 9 Mo / 40 / 0,4 s | 0,3 s / 0,2 s |
| `{namespace=~".+"} \|= "error"` | 2,1 Go / 4 900 / 24 s | 14 s / 3 s |
| Requête de Nadia : `sum by (namespace) (count_over_time({namespace=~".+"} \| json \| niveau="ERROR" [5m]))` | 2,1 Go / 4 900 / **expire à 60 s** | — (reformulée) |
| Requête de Nadia reformulée : `sum by (namespace) (count_over_time({namespace=~".+"} \|= "ERROR" \| json \| niveau="ERROR" [1h]))`, pas de 1 h | 2,1 Go lus, 90 % des lignes écartées avant l'analyseur JSON | 11 s / 2 s |

Ce qui a changé le résultat : filtre de ligne **avant** l'analyseur (l'analyse JSON est le poste le plus cher), fenêtre et pas de 1 h pour un tableau sur 7 jours (168 points au lieu de 2 016), cache des résultats.

## 4. Réglages

| Réglage | Retenu | Raison |
|---|---|---|
| `split_queries_by_interval` | 1h (au lieu de 15m du chart) | Un seul requêteur à 4 travailleurs : 672 sous-requêtes pour 7 jours saturaient la file ; 168 suffisent |
| `querier.max_concurrent` | 4 | 2 CPU demandés pour `loki-0` ; au-delà, contention sans gain mesuré |
| `query_timeout` | 2m | Les requêtes légitimes sur 7 jours tiennent en moins de 30 s ; 2 min laisse de la marge sans bloquer les travailleurs |
| Cache des résultats | intégré, 100 Mo | Pas de memcached dans le lab ; gain ×5 à ×7 sur les tableaux rejoués |
| `max_query_series` | 500 (défaut) | Aucun tableau légitime n'en approche |
| Cache des chunks intégré | **rejeté** | +300 Mo de mémoire pour un gain non mesurable (les chunks récents sont dans l'ingester) |
| `tsdb_max_query_parallelism` | défaut | Sans effet mesurable avec un seul pod |

## 5. Règles d'or pour les équipes

1. Toujours un sélecteur précis (`namespace`, `app`) ; jamais `{namespace=~".+"}` dans un tableau d'équipe.
2. Filtre de ligne (`|=`, `|~`) **avant** l'analyseur (`| json`, `| logfmt`).
3. Les identifiants (`request_id`, `trace_id`, utilisateur, rendez-vous) sont des **métadonnées structurées**, jamais des étiquettes.
4. Pour un tableau sur plusieurs jours : fenêtres et pas d'au moins 1 h ; les métriques fines viennent de Prometheus, pas des journaux.
5. Toute nouvelle étiquette passe par une MR dans `alloy/` relue par la plateforme.

## 6. Alertes

`plateforme/observabilite/regles/loki-capacite.yaml` : `LokiFluxActifsEleves` (seuils du § 1, 30 min) et `LokiEchantillonsRejetes` (10 min), testées par `promtool test rules` dans la CI.
