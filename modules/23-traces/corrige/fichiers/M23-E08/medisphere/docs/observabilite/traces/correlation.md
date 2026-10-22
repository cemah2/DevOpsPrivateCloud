# Corrélation métriques, journaux, traces

> `plateforme/medisphere`, `docs/observabilite/traces/correlation.md` — M23-E08 (DEV-2408).

## Les cinq chemins

| Depuis | Vers | Comment | Où c'est configuré |
|---|---|---|---|
| Une trace (Tempo) | ses journaux (Loki, locataire `mediagenda`) | bouton « Logs for this span » : `{namespace="<k8s.namespace.name>"} |= "<trace_id>"` | `grafana/sources-tempo.yaml` (`tracesToLogsV2`) |
| Une ligne de journal (Loki) | sa trace | métadonnée structurée `trace_id` → champ dérivé, lien interne vers la source `tempo` | `alloy/config.alloy` (`stage.structured_metadata`), `grafana/sources-loki.yaml` (`derivedFields`, `matcherType: label`) |
| Un point d'un graphe de latence (Prometheus) | la trace de cette requête | **exemplar** `trace_id` sur `mediagenda_http_request_duration_seconds` et `medidoc_http_request_duration_seconds` | applications (OpenMetrics), `kps/values.yaml` (`exemplar-storage`, `exemplarTraceIdDestinations`) |
| Un `request_id` (M22) | la trace | les deux identifiants sont sur la même ligne de journal | applications |
| Une trace | son profil (Pyroscope) | préparé : `tracesToProfiles` (M23-E14) | `grafana/sources-tempo.yaml` |

## Formats

`trace_id` : 32 caractères hexadécimaux minuscules ; `span_id` : 16 ; identiques dans Tempo, Loki et les exemplars (format W3C `traceparent`). Absents des lignes écrites hors requête (démarrage, arrêt).

## Limites connues

- Un exemplar peut désigner une trace **non gardée** par l'échantillonnage en queue (M23-E09) : « trace not found » pour ≈ 90 % des requêtes rapides et réussies. Les exemplars des requêtes lentes ou en erreur, celles qu'on cherche, mènent à une trace.
- Les exemplars restent dans la mémoire et le WAL de Prometheus (pas dans les blocs de Thanos) : quelques heures d'historique.
- Le lien Tempo → Loki ouvre le locataire `mediagenda` : pour une span de MédiDoc, ouvrir la source `Loki — medidoc` (ou une source multi-locataire, à décider avec l'équipe M22).
