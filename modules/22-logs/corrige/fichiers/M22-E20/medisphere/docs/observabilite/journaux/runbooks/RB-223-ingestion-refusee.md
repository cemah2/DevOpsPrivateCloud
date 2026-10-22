# RB-223 — Loki refuse les écritures

| | |
|---|---|
| Déclencheurs | Alerte `LokiEchantillonsRejetes` (M22-E14) ; lignes qui manquent dans Grafana alors que `kubectl logs` les montre ; Alloy qui journalise des erreurs d'envoi |
| Durée | 15 à 45 min |
| Références | politique des journaux § 2.2 (limites), RB-222 (journaux manquants), `loki/values.yaml` (`limits_config`, `runtimeConfig`) |

**Ce qui est en jeu** : Alloy réessaie un lot refusé (500 ms à 5 min, 10 fois par défaut) puis **l'abandonne**. Chaque minute de refus peut être une minute de journaux perdue.

## 1. Les deux côtés en une minute

```
admin@adm01:~$ kubectl -n journaux logs -l app.kubernetes.io/name=alloy --since=10m --prefix | grep -E 'status=(4|5)[0-9]{2}|error' | tail
admin@adm01:~$ promql 'sum by (tenant, reason) (rate(loki_discarded_samples_total[5m]))'      # ou l'Explore de Grafana
admin@adm01:~$ promql 'sum by (pod) (rate(loki_write_dropped_entries_total[5m]))'            # lignes abandonnées par Alloy
admin@adm01:~$ kubectl -n journaux logs loki-0 -c loki --since=15m | grep -E 'level=(error|warn)' | tail
```

(`promql` : alias de `curl -s -G $PROM/api/v1/query --data-urlencode query=…`, M21.)

## 2. Raison → preuve → correctif

| Code / raison | Message type (Loki 3.7) | Cause habituelle | Correctif |
|---|---|---|---|
| 429 `rate_limited` | `ingestion rate limit exceeded for user <locataire> (limit: N bytes/sec)` | `ingestion_rate_mb` / `ingestion_burst_size_mb` du locataire trop bas, ou rafale réelle (redémarrage massif, boucle d'erreurs) | Lire la surcharge du locataire (`kubectl -n journaux get cm loki-runtime …`) ; si elle est fautive : MR. Si le volume est réel : trouver le flux bavard (`topk(5, sum by (namespace, container) (bytes_rate({…}[5m])))`) avant de monter la limite **de ce locataire seulement** |
| 429 `stream_limit` | `maximum active stream limit exceeded when trying to create stream {…}` | `max_global_streams_per_user` sous le nombre de flux actifs, ou explosion de cardinalité (étiquette nouvelle) | `loki_ingester_memory_streams{tenant=…}` contre la limite ; `logcli series --analyze-labels` pour trouver l'étiquette qui explose ; corriger la source (Alloy) avant la limite |
| 429 `per_stream_rate_limit` | `Per stream rate limit exceeded (limit: …/sec) while attempting to ingest for stream '…'` | un seul flux dépasse 3 Mo/s | Le découpage automatique des flux (`shard_streams`) le traite au-delà du débit souhaité ; sinon, trouver pourquoi ce flux est si bavard |
| 400 `line_too_long` | `max entry size 'N' bytes exceeded for stream '…'` | ligne > `max_line_size` (256 Kio) | Ligne anormale (vidage d'objet) : corriger l'application ; sinon `max_line_size_truncate` |
| 400 `greater_than_max_sample_age` | `entry … has timestamp too old` | horloge décalée, agent qui rattrape un vieux journal, import | `chronyc tracking` sur la source ; `max_age` de l'agent ; jamais d'import de plus de 7 jours |
| 500, échecs de vidage | journal de `loki-0` : `SignatureDoesNotMatch`, `InvalidAccessKeyId`, `AccessDenied`, délais vers le RGW ; `loki_ingester_chunks_flush_failures_total` qui monte | identifiants du compartiment changés, RGW indisponible, politique réseau de sortie | § 3 |

## 3. Stockage objet

1. Le RGW répond-il ? `curl -s -o /dev/null -w '%{http_code}\n' https://rgw.par1.medisphere.internal` depuis `adm01` ; `ceph -s` sur `ceph-par1`.
2. Les identifiants du Secret sont-ils les bons ? Comparer **sans afficher** :
   ```
   admin@adm01:~$ kubectl -n journaux get secret loki-objstore -o jsonpath='{.data.LOKI_S3_SECRET_ACCESS_KEY}' | base64 -d | sha256sum
   admin@adm01:~$ (. ~/.config/workbook/s3-loki.env; printf '%s' "$AWS_SECRET_ACCESS_KEY" | sha256sum)
   ```
   Différents : recréer le Secret par `plateforme/k8s/outils/secrets-k8s.sh` (composant `loki`) à partir de Vault `critique`, **puis** redémarrer `loki-0` (les variables d'environnement ne se relisent pas) ; jamais de valeur à la main dans `kubectl`.
3. Après le redémarrage : le WAL est rejoué (`loki_ingester_wal_replay_active` repasse à 0), les vidages reprennent (`loki_ingester_chunks_flushed_total` monte), une requête sur hier répond.

## 4. Après

- Chiffrer la perte : `sum(increase(loki_write_dropped_entries_total[<durée de l'incident>]))` ; dire aux équipes quelle fenêtre est incomplète.
- Ce qui ne se fait jamais : lever toutes les limites de tous les locataires « pour voir » ; supprimer le WAL ou le PVC pour « débloquer » Loki.
