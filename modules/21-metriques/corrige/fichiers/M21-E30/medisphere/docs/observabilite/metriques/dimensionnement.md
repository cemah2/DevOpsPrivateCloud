# Dimensionnement de Prometheus et de Thanos

| | |
|---|---|
| Ticket | PLAT-2230 (M21-E30) |
| Mesures | `plateforme/observabilite`, `requetes/E30.promql` (Q1 à Q11), relevées le `<DATE>` sur 7 jours |
| Réglages | `kps/values.yaml` (limites, rétention, ressources), `thanos/thanos-query.yaml` (limites), `regles/capacite-prometheus.yaml` (alertes) |
| Révision | à chaque nouvel environnement ou nouvelle équipe supervisée, et si `PrometheusSeriesProchesDuBudget` sonne |

> Les nombres ci-dessous sont ceux du lab de la rédaction : **remplace-les par tes mesures**. La méthode compte plus que les valeurs.

## 1. Mesures (par réplica)

| Grandeur | Requête | Valeur |
|---|---|---|
| Séries actives | Q1 | ~150 000 |
| Échantillons ingérés | Q2 | ~5 000 /s (150 000 séries / 30 s) |
| Octets par échantillon sur disque | Q3 | ~1,3 o |
| Mémoire résidente par série | Q4 | ~10 Kio (tête, index, caches, Go : tout compris) |
| Pic mémoire sur 7 jours | Q5 | ~2,2 Gio |
| Plus grosse cible | Q8 | kube-state-metrics, ~18 000 échantillons par collecte |
| Étiquettes par série | (`count by (__name__)` + lecture) | 14 au plus (cAdvisor) |

## 2. Disque

Formule de la documentation de Prometheus : `espace = rétention (s) × échantillons/s × octets/échantillon`.

15 j × 86 400 s × 5 000 /s × 1,3 o ≈ **8,4 Go** de blocs, plus le WAL (≈ 2 à 3 h d'échantillons non compressés, quelques Go au pic) et la marge des compactions locales : volume de **40 Gio** confortable ; `retentionSize: 30GB` garde ~25 % de marge sous le volume. Le volume ne se remplit donc pas avant 15 jours **sauf** explosion de cardinalité : c'est `retentionSize` qui protège alors l'écriture du WAL (un volume plein arrête la collecte de ce réplica).

Compartiment Thanos (`thanos-k8s-par1`, deux réplicas avant dédoublonnage, puis un) : brut 30 j ≈ 2 × 17 Go avant compaction, ~17 Go après dédoublonnage ; 5 min sur 180 j et 1 h sur 2 ans : quelques Go. **Quota RGW de 40 Gio** suffisant ; à relire si les séries doublent. Mesure : `aws s3 ls s3://thanos-k8s-par1 --recursive --summarize | tail -2` (identité `thanos`).

## 3. Mémoire et budget de séries

Avec ~10 Kio par série mesurés, une limite de **3 Gio** tient ~300 000 séries en régime établi ; la relecture du WAL au démarrage et une requête lourde demandent davantage, d'où :

- demande `2Gi` (pic mesuré : le planificateur réserve vraiment), limite `3Gi` ;
- **budget : 300 000 séries actives par réplica** ; alerte `PrometheusSeriesProchesDuBudget` à 80 % (240 000) ;
- deux réplicas : 2 × 2 Gio réservés sur les travailleurs (10 Go chacun, M19) — à mettre en regard du profil de 100 Go (PLAN §4.11).

## 4. Rétention locale et SLO sur 28 jours

Rétention locale **15 jours** (PLAN). Conséquence (voir `slo.md`) : la règle `…:increase4w` de Pyrra ne voit que 15 jours. Options étudiées :

| Option | Coût | Décision |
|---|---|---|
| Rétention locale 29 j | ~2 × 16 Go de blocs, volume 60 Gio, relecture plus longue au démarrage | non retenue pour le lab (capacité de `ceph-par1`) ; recommandée en production réelle |
| Thanos Ruler qui évalue les règles de Pyrra sur Thanos Query (28 j réels) | un composant de plus, règles hors Prometheus | reportée (ADR-0210, conséquences) |
| Accepter « 28 j » = 15 j au plus | interprétation à écrire dans les rapports | **retenue** jusqu'à la révision |

## 5. Garde-fous de collecte et de requêtes

| Réglage | Valeur | Pourquoi |
|---|---|---|
| `scrapeInterval` | 30 s | défaut, gardé ; fenêtres `rate()` ≥ 2 min dans les règles |
| `enforcedSampleLimit` | 50 000 | plus grosse cible × 2,5 ; une cible qui explose est mise en échec (`up=0`) au lieu de saturer Prometheus |
| `enforcedLabelLimit` / `enforcedLabelValueLengthLimit` | 40 / 512 | 14 étiquettes au plus mesurées ; valeurs longues = identifiants (cardinalité) |
| `enforcedBodySizeLimit` | 50 MB | réponse `/metrics` aberrante |
| `query.maxSamples` / `query.timeout` / `query.maxConcurrency` | 20 M / 1 min / 10 | une requête trop large échoue vite au lieu d'emporter la mémoire des deux réplicas |
| Thanos Query `--store.limits.request-samples` / `request-series` | 20 M / 500 000 | même logique, par point d'accès ; le Store lit le compartiment |

Quand une cible dépasse : `PrometheusLimiteEchantillonsAtteinte`. Trouver la cible (`up == 0` et `scrape_samples_scraped` élevé), puis avec l'équipe : relabeling (`metricRelabelings` qui retire l'étiquette fautive), jamais une hausse de la limite sans comprendre (M21-E38).

## 6. Ce qui ferait changer ces choix

- plus de 240 000 séries par réplica (nouvel environnement, nouvelles équipes) : shards (`shards: 2`) avant d'augmenter la mémoire au-delà de 4 Gio ;
- besoin de requêtes longues fréquentes : Thanos Query Frontend (cache, découpage) ;
- production réelle : rétention locale ≥ fenêtre des SLO, compartiment répliqué hors site (F5).
