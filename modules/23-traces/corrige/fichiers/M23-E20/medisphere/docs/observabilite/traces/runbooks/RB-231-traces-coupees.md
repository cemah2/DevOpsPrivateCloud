# RB-231 — Traces coupées en morceaux

**Symptôme** : une trace s'arrête au client HTTP d'un service ; la partie du service appelé manque ou forme une trace à part (span sans parent, racine dans le service appelé) ; le graphe de services perd une arête.

## 1. Constater

```
# TraceQL (Grafana → Explore → Tempo), sur 30 min :
{resource.service.name = "mediagenda-api"} >> {resource.service.name = "medidoc"}     # traces entières
{trace:rootService = "medidoc"}                                                     # MédiDoc orphelin
{resource.service.name = "mediagenda-api" && kind = client && span.server.address =~ "medidoc.*"}  # appels émis
```

Ouvre une trace « orpheline » de MédiDoc : la span racine a-t-elle un `parentSpanId` (parent perdu en route) ou aucun (contexte jamais reçu) ?

## 2. Trois familles de causes

| Cause | Preuve | Correctif |
|---|---|---|
| **Propagation** : l'appelant n'injecte pas `traceparent` (propagateurs, `OTEL_PROPAGATORS` sans `tracecontext`), ou un relais (proxy, passerelle) retire l'en-tête | variables des pods ; journal de MédiDoc avec les en-têtes reçus en DEBUG, ou `tcpdump`/Hubble L7 sur le port 8080 | `OTEL_PROPAGATORS=tracecontext,baggage` (ou rien : c'est la valeur par défaut) ; configurer le relais pour transmettre `traceparent`, `tracestate`, `baggage` |
| **Échantillonnage incohérent** : le service appelé n'utilise pas un échantillonneur `parentbased_*` et décide seul | `OTEL_TRACES_SAMPLER` des pods du service appelé | `parentbased_traceidratio` partout (ou `parentbased_always_on`) : la décision du parent s'impose |
| **Échantillonnage en queue sans équilibrage** : les spans d'une trace arrivent sur des réplicas différents de la passerelle, chacun décide sur une trace partielle | configuration de l'agent : exportateur `loadbalancing` (clé `traceID`) ou envoi direct au Service ClusterIP ; `otelcol_processor_tail_sampling_*` par réplica | exportateur `loadbalancing` vers le Service **sans tête** de la passerelle, résolveur `k8s` |

## 3. Vérifier et clore

Traces entières sur 15 min, aucune racine MédiDoc pour les appels venant de MédiAgenda, arête visible dans le graphe de services ; `lab/bin/check 23 20`.

## Prévention

Variables `OTEL_*` posées par un seul composant kustomize (`components/telemetrie`) ; test de propagation dans la CI des applications (requête de bout en bout et vérification du `traceparent` reçu) ; alerte sur la part de traces enracinées dans un service qui ne reçoit pas de trafic direct.
