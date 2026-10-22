# RB-235 — Plus aucune trace

**Alerte** : `TracesAbsentes` (critique) ou signalement « Grafana ne trouve plus de traces de <service> ».
**Impact** : diagnostic des incidents dégradé ; aucun impact pour les patients. **Équipe** : plateforme.

## 1. Délimiter (5 min)

```
admin@adm01:~$ # Tous les services, ou un seul ? Tous les environnements, ou un seul ?
# Grafana → Explore → Tempo : {resource.service.name = "mediagenda-api"} puis sans filtre, sur 1 h
# Prometheus (10.10.41.60) :
sum by (job) (rate({__name__=~"otelcol_receiver_accepted_spans(_total)?"}[5m]))
sum by (job, exporter) (rate({__name__=~"otelcol_exporter_sent_spans(_total)?|otelcol_exporter_send_failed_spans(_total)?"}[5m]))
```

Lecture : les agents reçoivent-ils (accepted) ? la passerelle reçoit-elle ? la passerelle envoie-t-elle à Tempo (sent) ou échoue-t-elle (send_failed) ? Le premier maillon à zéro est le coupable.

## 2. Selon le maillon

| Maillon muet | Vérifier | Commandes |
|---|---|---|
| Application → agent | point d'accès et protocole OTLP de l'application (4317 = gRPC, 4318 = HTTP), journaux de l'application (erreurs d'export du SDK) | `kubectl -n <espace> get deploy <app> -o yaml \| grep -A1 OTEL_EXPORTER` ; `kubectl -n <espace> logs deploy/<app> \| grep -i -E 'export|otlp'` ; historique de l'overlay : `git log -p overlays/<env>` |
| Agent (récepteur) | protocoles du récepteur `otlp` de l'agent, pods prêts | `kubectl -n traces get otelcol otel-agent -o jsonpath='{.spec.config.receivers}'` ; `kubectl -n traces get ds otel-agent-collector` |
| Agent → passerelle | politiques réseau de `traces` (règles de refus comprises), Hubble | `kubectl -n traces get cnp` ; `hubble observe -n traces --to-port 4317 --verdict DROPPED` |
| Passerelle → Tempo | adresse de l'exportateur, résolution DNS, Tempo prêt | `kubectl -n traces logs deploy/otel-passerelle-collector \| grep -i -E 'export|dial|no such host'` ; `kubectl -n traces get pods -l app.kubernetes.io/name=tempo` |

## 3. Corriger

Toujours **par le code** : `plateforme/observabilite/otel/` (Collectors), `…/deploiement` (variables des applications), puis laisser Argo CD synchroniser (`argocd app get otel`). Une politique réseau ajoutée à la main se supprime après avoir retrouvé qui l'a posée et pourquoi (annotation, ticket).

## 4. Vérifier et clore

- Traces récentes dans Tempo pour chaque service ; `otelcol_exporter_send_failed_spans` à zéro.
- `lab/bin/check 23 19`.
- Les traces de la période de panne sont perdues : le noter dans le ticket (pas de rattrapage possible).

## Prévention

- Alerte `TracesAbsentes` et `CollectorPerdDesSpans` (`regles/traces-collectors.yaml`).
- Validation des configurations en CI (`otelcol-contrib validate`) ; revue des MR qui touchent `OTEL_*`.
