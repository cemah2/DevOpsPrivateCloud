# Échantillonnage des traces

> `plateforme/medisphere`, `docs/observabilite/traces/echantillonnage.md` — M23-E09 (PLAT-2409).

## Règle

| Où | Quoi | Réglage |
|---|---|---|
| En tête (SDK des applications) | `parentbased_traceidratio`, ratio **1.0** | `OTEL_TRACES_SAMPLER`, `OTEL_TRACES_SAMPLER_ARG` (component `telemetrie`) |
| En queue (`otel-passerelle`, 2 réplicas) | gardées : 100 % des traces avec une erreur, 100 % des traces > 500 ms, 10 % du reste | `tail_sampling` (`decision_wait` 10 s, `num_traces` 20 000) |
| Routage | toutes les spans d'une trace vers le **même** réplica | exportateur `loadbalancing` des agents, `routing_key: traceID`, résolveur `k8s` sur `otel-passerelle-collector-headless` |

Pourquoi 1.0 en tête : la décision en tête est prise **avant** de savoir si la requête échouera ou sera lente ; à 0.1, on perdrait 90 % des erreurs. Le volume est réduit en queue, où l'on connaît l'issue. `parentbased_*` : un service appelé suit la décision de son appelant (sinon des traces « trouées »).

## Ce qu'il faut surveiller

| Métrique | Signification |
|---|---|
| `otelcol_processor_tail_sampling_global_count_traces_sampled` (par `sampled`) | décisions prises |
| `otelcol_processor_tail_sampling_sampling_trace_dropped_too_early` | traces décidées de force (mémoire pleine) : monter `num_traces` ou la mémoire |
| `otelcol_exporter_send_failed_spans{exporter="loadbalancing/passerelle"}` | réplica injoignable |
| `otelcol_loadbalancer_num_backends` | réplicas vus par chaque agent (doit valoir 2) |

Noms exacts : à relire sur `/metrics` des Collectors de ta version (ils changent d'une mineure à l'autre).

## Conséquences

Compter des requêtes à partir des traces est **faux** après échantillonnage : le *metrics-generator* de Tempo (M23-E13) ne voit que les traces gardées (sous-comptage des requêtes rapides et réussies, surreprésentation des lentes). Les taux et les SLO restent calculés sur les métriques des applications (M21). Les exemplars peuvent désigner des traces jetées (M23-E08).
