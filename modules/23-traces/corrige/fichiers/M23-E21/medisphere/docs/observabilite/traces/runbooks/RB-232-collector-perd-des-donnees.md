# RB-232 — Le Collector perd des données

**Alertes** : `CollectorPerdDesSpans` (critique), `CollectorRefuseDesSpans`, `CollectorFileDAttentePleine`.
**Impact** : traces manquantes ou incomplètes, en particulier pendant les pics (donc pendant les incidents).

## 1. Où se perdent les spans ?

```
# Prometheus (10.10.41.60), par Collector (job) :
sum by (job, receiver)  (rate({__name__=~"otelcol_receiver_(accepted|refused|failed)_spans(_total)?"}[5m]))
sum by (job)            (rate({__name__=~"otelcol_processor_memory_limiter_refused_spans(_total)?"}[5m]))
sum by (job, exporter)  (rate({__name__=~"otelcol_exporter_(sent|send_failed|enqueue_failed)_spans(_total)?"}[5m]))
max by (job, exporter)  (otelcol_exporter_queue_size / otelcol_exporter_queue_capacity)
sum by (reason)         (rate(tempo_discarded_spans_total[5m]))
```

| Signe | Cause probable | Correctif (par le code, `plateforme/observabilite`) |
|---|---|---|
| `memory_limiter_refused` > 0 en continu, mémoire du pod loin de sa limite | `memory_limiter` trop bas (`limit_mib` sous la consommation normale) | `limit_percentage: 80`, `spike_limit_percentage: 20` (relatif à la limite du conteneur) ; vérifier la limite mémoire du conteneur |
| `memory_limiter_refused` > 0 pendant les pics, mémoire au plafond | passerelle sous-dimensionnée, `tail_sampling` trop gourmand (`num_traces`, `decision_wait`) | plus de mémoire ou de réplicas ; réduire `decision_wait` |
| `enqueue_failed` > 0, file à 100 % | destination lente ou en panne, file trop petite (`queue_size`), trop peu de consommateurs | réparer la destination ; file dimensionnée en `items` (dizaines de milliers), `num_consumers` 4 à 10 |
| `send_failed` > 0, journal « RATE_LIMITED » ou « exceeded while adding N bytes » | limite d'ingestion de Tempo (`rate_limit_bytes`) ou **lot plus gros que la rafale** (`burst_size_bytes`) | lots bornés (`send_batch_max_size`) sous la rafale ; relever la limite de Tempo si le débit est légitime |
| `send_failed` > 0, « message larger than max » | lot plus gros que la taille de message du récepteur suivant | même logique : borner les lots |
| Tempo lent (latence d'ingestion), file qui monte | Tempo saturé, délai artificiel (`artificial_delay`), RGW lent | `overrides` de Tempo, ressources, état du RGW |

Journaux : `kubectl -n traces logs deploy/otel-passerelle-collector --since=15m | grep -i -E 'refused|dropping|queue is full|RATE_LIMITED|exceeded'`.

## 2. Vérifier et clore

Les compteurs de refus et de pertes restent à zéro 15 min sous trafic normal ; files sous 50 % ; `lab/bin/check 23 21`.

## Prévention

Toute modification de `memory_limiter`, de `sending_queue`, de `batch` ou des `overrides` de Tempo passe par une MR relue avec le tableau « Pipeline de traces » ; un essai de charge (M29) avant de toucher aux limites.
