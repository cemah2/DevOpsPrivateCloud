# Chaîne des traces de `k8s-par1`

> Dépôt `plateforme/medisphere`, `docs/observabilite/traces/architecture.md` — M23-E02 (PLAT-2402), complété par M23-E03 (Tempo), M23-E09 (échantillonnage) et M23-E16 (entrée externe sécurisée).

## Schéma

```
 pod applicatif (SDK OpenTelemetry)              hors cluster (adm01 aujourd'hui ; VMs au M23-E16)
   │ OTLP gRPC 4317, sans TLS                          │ OTLP 4317/4318
   │ http://otel-agent-collector.traces.svc:4317       │ 10.10.41.63 otlp.apps.par1.medisphere.internal
   ▼ (internalTrafficPolicy: Local → agent du nœud)    ▼ Service otlp-externe (LoadBalancer, ETP Local)
 otel-agent (DaemonSet, un par travailleur)            │
   memory_limiter → k8sattributes → resourcedetection  │
   → resource/cluster → batch                          │
   │ OTLP gRPC 4317                                    │
   ▼                                                   ▼
 otel-passerelle (Deployment, 1 réplica ; 2 au M23-E09)
   memory_limiter → batch → [debug en M23-E02] / otlp_grpc → Tempo (M23-E03)
```

## Objets

| Objet | Où | Rôle |
|---|---|---|
| Application `opentelemetry-operator` | `opentelemetry-operator-system` | opérateur 0.161.0 (chart 0.126.1 recopié dans Harbor `charts/`), webhooks par cert-manager |
| Application `otel` | `traces` | `plateforme/observabilite/otel/` : Collectors, RBAC, Service, politiques, ServiceMonitor |
| `OpenTelemetryCollector/otel-agent` | `traces` | mode `daemonset`, compte `otel-agent` (ClusterRole `otel-agent-k8sattributes`) |
| `OpenTelemetryCollector/otel-passerelle` | `traces` | mode `deployment` |
| Services créés par l'opérateur | `traces` | `otel-agent-collector` (local au nœud), `otel-passerelle-collector`, `…-headless`, `…-monitoring` (8888) |
| `Service/otlp-externe` | `traces` | 10.10.41.63, 4317/4318 → passerelle |
| `CiliumNetworkPolicy` `traces-agent`, `traces-passerelle` | `traces` | entrées autorisées (le reste est refusé) |
| `CiliumClusterwideNetworkPolicy/telemetrie-vers-otel-agent` | cluster | sortie des espaces applicatifs vers l'agent (4317/4318), sans refus par défaut |
| `ServiceMonitor/otel-collectors` | `traces` | métriques `otelcol_*` dans Prometheus |

Image des Collectors : `registry.par1.medisphere.internal/dockerhub/otel/opentelemetry-collector-contrib:0.161.0` (distribution *contrib* : `k8sattributes`, `tail_sampling`, `loadbalancing` n'existent pas dans la distribution de base).

## Flux

| Source | Destination | Port | Où c'est autorisé |
|---|---|---|---|
| pods de `mediagenda-*`, `medidoc-*`, `wb-essais` | `otel-agent` | TCP 4317, 4318 | CCNP `telemetrie-vers-otel-agent` + CNP `traces-agent` |
| `otel-agent` | `otel-passerelle` | TCP 4317 | CNP `traces-passerelle` |
| `otel-agent` | API Kubernetes | TCP 6443 | sorties non filtrées dans `traces` (M23-E16) |
| MGMT (10.10.10.0/24) | 10.10.41.63 | TCP 4317, 4318 | bordure (MGMT → tout, M00) + CNP `traces-passerelle` |
| Prometheus (`supervision`) | agents et passerelle | TCP 8888 | CNP `traces-agent`, `traces-passerelle` |

Reportés dans `docs/kubernetes/reseau/matrice-flux-cluster.md`.

## Vérifier

```
kubectl -n traces get opentelemetrycollectors
kubectl -n traces get pods -l app.kubernetes.io/component=opentelemetry-collector -o wide
sum by (receiver) (rate(otelcol_receiver_accepted_spans[5m]))       # Prometheus
sum by (exporter) (rate(otelcol_exporter_send_failed_spans[5m]))    # doit rester à 0
```
