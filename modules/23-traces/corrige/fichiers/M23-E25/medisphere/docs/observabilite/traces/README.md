# Traces et profils — MédiSphère v1 (`traces-v1`)

> Exemple du corrigé : la page d'accueil que l'astreinte ouvre en premier. Adresses et noms conformes au PLAN.

## Ce qui tourne

| Composant | Où | Géré par |
|---|---|---|
| OpenTelemetry Operator 0.16x | espace `opentelemetry-operator-system` | Application `opentelemetry-operator` |
| `otel-agent` (DaemonSet), `otel-passerelle` (2 réplicas, échantillonnage en queue) | espace `traces` | Application `otel` (`plateforme/observabilite/otel/`) |
| Tempo 3.1 monolithique, *metrics-generator* | espace `traces`, compartiment `tempo-k8s-par1` (14 j) | Application `tempo` (`tempo/values.yaml`) |
| Pyroscope 2.4 | espace `traces`, compartiment `pyroscope-k8s-par1` (14 j) | Application `pyroscope` |
| Point d'entrée hors cluster | `otlp.apps.par1.medisphere.internal` = 10.10.41.63:4317/4318, TLS + jeton | Service `otlp-externe` |
| Sources Grafana `Tempo`, `Pyroscope`, liens vers `Loki — <équipe>` et Prometheus | `grafana.apps.par1.medisphere.internal` | `grafana/sources-*.yaml` |

Applications instrumentées : MédiAgenda (`mediagenda-api`, dev/recette/prod), MédiDoc (`medidoc`, dev/recette), par le composant kustomize `components/telemetrie` (et `components/profilage`) de leur dépôt `…/deploiement`.

## Où trouver quoi

- Décision et options écartées : [ADR-0230](adr/ADR-0230-traces-et-profilage.md).
- Règles d'instrumentation, attributs interdits : [conventions-telemetrie.md](conventions-telemetrie.md).
- Capacité, rétention, jetons, flux : [capacite-securite.md](capacite-securite.md) ; métriques tirées des traces : [metriques-depuis-traces.md](metriques-depuis-traces.md) ; profilage : [profilage.md](profilage.md).
- Preuves de conformité : [conformite.md](conformite.md) ; démonstration du parcours complet : [demonstration.md](demonstration.md).
- Runbooks : [RB-230 plus aucune trace](runbooks/RB-230-plus-aucune-trace.md), [RB-231 traces coupées](runbooks/RB-231-traces-coupees.md), [RB-232 le Collector perd des données](runbooks/RB-232-collector-perd-des-donnees.md), [RB-233 lien trace ↔ journaux](runbooks/RB-233-lien-trace-journaux.md).
- Tableaux : « MédiAgenda — SLO, traces et profils » (`m23-slo-traces`), « MédiAgenda — RED depuis les traces » (`m23-red-traces`), « Pipeline de traces ».
- Alertes : `regles/traces-collectors.yaml` (`TracesAbsentes`, `CollectorPerdDesSpans`, `CollectorRefuseDesSpans`, `CollectorFileDAttentePleine`).

## Pour les modules suivants

- F3 (astreinte) : le parcours alerte → exemplar → trace → journaux → profil est rodé (demonstration.md).
- M24 : SSO de Grafana (les équipes remplacent les comptes locaux), OIDC à étudier pour le point d'entrée OTLP.
- M26 : chiffrement des flux internes, filtrage des sorties de l'espace `traces`, OBI à réévaluer.
- M29 : les essais de charge et de chaos s'observent avec ces tableaux ; les limites de la chaîne (M23-E16) y seront éprouvées.
