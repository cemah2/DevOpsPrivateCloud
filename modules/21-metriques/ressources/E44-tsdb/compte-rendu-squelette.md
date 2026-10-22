# La TSDB de Prometheus sous le capot (témoin de mon01)

> Squelette du compte rendu de M21-E44 (PLAT-2244). Copie-le dans
> `docs/observabilite/metriques/analyses/tsdb-sous-le-capot.md` de `~/medisphere`, remplis chaque
> section avec TES relevés (commande, sortie utile, chiffre), réponds aux questions, publie par MR.
> Ni secret, ni contenu de configuration sensible : des noms, des chiffres, des explications.

Contexte : version du Prometheus témoin, rétention, intervalle de collecte, date et heure de
l'instantané, nom de l'instantané, heures d'ouverture et de fermeture de l'API d'administration
(références des MR).

## Le WAL et la tête

- Contenu de `/var/lib/prometheus/data` (tableau : élément, rôle, relevé).
- Segments du WAL, checkpoint (numéro, heure), `chunks_head/`.
- Métriques relevées : `prometheus_tsdb_head_series`, `prometheus_tsdb_head_chunks`,
  `prometheus_tsdb_head_min_time`/`max_time`, `prometheus_tsdb_wal_segment_current`.
- Le chemin d'un échantillon, de la collecte au bloc (en quelques phrases).

## Les blocs

- Sortie de `promtool tsdb list -r` (extrait commenté).
- Un `meta.json` lu : `minTime`, `maxTime`, `stats`, `compaction.level`, `compaction.sources`.
- Les fichiers d'un bloc et leur rôle (`index`, `chunks/`, `tombstones`).
- Décodage d'un ULID et comparaison avec les dates du bloc.

## La compaction et la rétention

- Durées de blocs observées, niveau de compaction, plafond calculé pour la rétention du témoin.
- Ce qui change dans le cluster avec Thanos (durée des blocs, qui compacte).
- Ce que la rétention supprime, et quand.

## Analyse et cardinalité

- `promtool tsdb analyze` : séries, étiquettes, métriques les plus coûteuses, churn.
- `--extended` : échantillons par chunk ; interprétation.
- `promtool tsdb dump` sur une série et une heure : nombre d'échantillons, intervalle retrouvé.
- Coût d'une série (disque, mémoire) et comparaison avec M21-E38.

## Réponses aux questions

1. …
2. …
3. …
4. …
5. …
6. …
7. …
8. …
