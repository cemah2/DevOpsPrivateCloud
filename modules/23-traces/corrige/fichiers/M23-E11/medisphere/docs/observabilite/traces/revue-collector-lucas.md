# Revue de la MR !57 « collectors-v2 » (Lucas Martin)

> `plateforme/medisphere`, `docs/observabilite/traces/revue-collector-lucas.md` — M23-E11 (PLAT-2411). Revue : <MOI>, relue par Karim Benali. Décision : **MR refusée en l'état**, reprise à partir des Collectors de référence (M23-E09/E10).

| # | Où | Constat | Gravité | Correction |
|---|---|---|---|---|
| 1 | `otel-passerelle`, exportateur `otlphttp/infoger` | les traces partent chez un tiers (InfoGér), hors de MédiSphère, **en clair** (`http://`, `tls.insecure`) | bloquant (HDS, RGPD, souveraineté) | supprimé ; tout export hors du lab passe par une décision écrite de Sophie Laurent (ADR) |
| 2 | `otel-agent` | aucun `memory_limiter` : un pic de spans fait tuer le pod (OOMKilled), les spans de tout le nœud sont perdues | bloquant | `memory_limiter` en premier, limite de mémoire du conteneur |
| 3 | `otel-passerelle`, pipeline | `batch` **avant** `memory_limiter` : les données sont déjà en mémoire quand le limiteur décide | majeur | `memory_limiter` en premier, `batch` en dernier |
| 4 | `otel-passerelle`, `memory_limiter` | `limit_mib: 4000` sans limite de conteneur (et le nœud n'a que 10 Go) | majeur | `limit_percentage` + `resources.limits.memory` |
| 5 | `otel-passerelle`, exportateur `debug` | `verbosity: detailed` dans le pipeline de production : chaque span (attributs compris) écrite dans les journaux du pod, donc dans Loki | bloquant (données) | supprimé |
| 6 | les deux | anciens noms `otlp` / `otlphttp` : alias dépréciés depuis la 0.144 (le Collector l'écrit au démarrage : `"otlp" alias is deprecated; use "otlp_grpc" instead`) | mineur | `otlp_grpc`, `otlp_http` |
| 7 | `otel-passerelle` | `tail_sampling` sur **2 réplicas** alimentés par le Service ordinaire : les spans d'une même trace se répartissent au hasard, chaque réplica décide sur une trace incomplète | majeur | exportateur `loadbalancing` (`routing_key: traceID`) dans les agents, Service sans tête |
| 8 | `otel-agent` | `probabilistic_sampler` à 10 % **avant** l'échantillonnage en queue : 90 % des erreurs sont jetées avant qu'on sache que ce sont des erreurs ; double échantillonnage | majeur | supprimé ; décision en queue seulement |
| 9 | `otel-agent` | `k8sattributes` sans compte de service ni RBAC : « forbidden » dans les journaux, aucun enrichissement | majeur | compte `otel-agent`, ClusterRole en lecture (pods, namespaces, replicasets, nodes) |
| 10 | `otel-agent`, `k8sattributes.extract.annotations` | **toutes** les annotations des pods recopiées en attributs (configurations, sommes de contrôle, parfois des secrets) ; cardinalité | majeur | liste fermée de métadonnées, une étiquette d'espace (`medisphere.internal/equipe`) |
| 11 | `otel-agent`, exportateur | `sending_queue` et `retry_on_failure` désactivés : une seconde d'indisponibilité de la passerelle = spans perdues | majeur | file d'attente et reprises |
| 12 | `otel-agent`, `batch` | `send_batch_size: 100000` sans `send_batch_max_size` : messages gRPC au-delà de 4 Mio (refusés par le récepteur), latence de 30 s | majeur | 512 spans / 2 s dans l'agent, 1024 / 5 s dans la passerelle |
| 13 | `Service/otel-lucas` | `LoadBalancer` sans adresse demandée ni politique : réception OTLP **sans authentification** ouverte, plus `zpages` (55679) et `pprof` (1777) publiés sur `0.0.0.0` | bloquant (sécurité) | Service `otlp-externe` (10.10.41.63) + CNP ; extensions de diagnostic jamais publiées |
| 14 | les deux | image `otel/opentelemetry-collector-contrib:latest` : refusée par la politique `medisphere-images` (hors Harbor, sans version) | bloquant | `registry.par1.medisphere.internal/dockerhub/otel/opentelemetry-collector-contrib:0.161.0` |
| 15 | `otel-passerelle` | `service.telemetry.metrics.level: none` : aucune métrique interne, on ne voit ni les refus ni les pertes | majeur | lecteur Prometheus sur 8888 + ServiceMonitor |
| 16 | les deux | ni `health_check` ni ressources ni contexte de sécurité : pas de sondes, refus par Pod Security `restricted` | majeur | voir les CR de référence |
| 17 | les deux | aucun masquage (`url.query`, littéraux SQL, en-têtes) | majeur | `transform/masquage`, `redaction` (M23-E10) |

Ce que la MR faisait bien : un Collector par nœud plus une passerelle (la bonne architecture), l'échantillonnage en queue avec une politique « erreurs », le récepteur HTTP en plus du gRPC.
