# RB-224 — Requêtes Loki lentes ou en échec

| | |
|---|---|
| Déclencheurs | Tableau Grafana en erreur ; requêtes qui expirent dans Explore ; `logcli` qui échoue |
| Durée | 15 à 30 min |
| Références | `performance.md` (mesures et réglages de M22-E14), `loki/values.yaml` (`limits_config`, `runtimeConfig`) |

## 1. Reproduire hors de Grafana

```
admin@adm01:~$ export LOKI_ADDR=http://loki.apps.par1.medisphere.internal:3100
admin@adm01:~$ curl -s -G -H 'X-Scope-OrgID: <LOCATAIRE>' $LOKI_ADDR/loki/api/v1/query_range \
    --data-urlencode 'query=<REQUÊTE>' --data-urlencode since=24h -w '\nHTTP %{http_code}\n' | tail -2
admin@adm01:~$ logcli query --org-id=<LOCATAIRE> --since=24h --stats --quiet '<REQUÊTE>' >/dev/null
```

Toujours comparer : le même locataire sur une plage plus courte, un autre locataire sur la même plage.

## 2. Message → limite

| HTTP | Message (Loki 3.7) | Limite | Lire la valeur effective |
|---|---|---|---|
| 504 | `request timed out, decrease the duration of the request or add more label matchers…` | `query_timeout` | `/config/tenant/v1/limits` (en-tête du locataire) |
| 400 | `the query time range exceeds the limit (query length: 24h0m0s, limit: 6h)` | `max_query_length` | idem |
| 400 | `maximum number of series (N) reached for a single query…` | `max_query_series` | idem |
| 400 | `max entries limit per query exceeded, limit > max_entries_limit (…)` | `max_entries_limit_per_query` | idem |
| 400 | `the query would read too many bytes (query: …, limit: …)` | `max_query_bytes_read` / `max_querier_bytes_read` | `/config`, ConfigMap `loki-runtime` |
| 200 mais vide au-delà d'une date | — | `max_query_lookback` (voir RB-222 § 2.3) | idem |
| lent sans erreur | — | découpage (`split_queries_by_interval`), parallélisme, cache | `/config` (`limits_config`, `query_range`) |

Une limite vient soit de `limits_config` (tous les locataires), soit d'une **surcharge** du locataire (`runtimeConfig.overrides.<locataire>`) : `git log -p -- loki/values.yaml` dit laquelle a bougé et qui l'a changée.

## 3. Lire les statistiques (`--stats`, *Query inspector → Stats*)

- `Querier.TotalChunksRef` / `TotalChunksDownloaded` : combien de chunks le sélecteur ramène → sélecteur trop large ?
- `Summary.TotalBytesProcessed` et `ExecTime` : volume décompressé et temps → filtres et analyseurs.
- `Ingester.TotalReached` : part servie par l'ingester (dernières heures).

## 4. Alléger avant d'augmenter

1. Sélecteur précis (`namespace`, `app`), jamais `{namespace=~".+"}` dans un tableau d'équipe.
2. Filtre de ligne avant l'analyseur : `|= "ERROR" | json | niveau="ERROR"`.
3. Pour plusieurs jours : fenêtres et pas d'au moins 1 h ; ou une règle d'enregistrement du *ruler*.
4. Une limite ne se monte que **pour le locataire concerné**, avec la mesure qui le justifie, par MR ; une limite trop basse posée par erreur se remet à sa valeur de `performance.md`.

## 5. Clore

`lab/bin/check 22 21` ; ajouter la requête fautive et sa reformulation à `performance.md`.
