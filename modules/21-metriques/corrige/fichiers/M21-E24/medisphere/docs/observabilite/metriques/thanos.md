# Thanos : conservation longue et vue globale des métriques

| | |
|---|---|
| Ticket | PLAT-2224 (M21-E24), PLAT-2225 (M21-E25) |
| Propriétaire | Équipe Plateforme |
| Code | `plateforme/observabilite` : `thanos/` (Query, Store, Compactor), `kps/values.yaml` (sidecar, 2 réplicas) |
| Secrets | Secret `supervision/thanos-objstore` (composant `thanos` de `plateforme/k8s/outils/secrets-k8s.sh`, Vault `critique` `secrets/thanos.yml`) ; `~/.config/workbook/s3-thanos.env` sur `adm01` |
| Runbook | [RB-214 — Thanos : les blocs n'arrivent plus ou le Compactor est arrêté](runbooks/RB-214-thanos.md) |

## Architecture

```
            MGMT, mon01 ──▶ 10.10.41.60:9090 (prometheus.apps.par1.medisphere.internal)
                                   │            Grafana, Pyrra ──▶ thanos-query:9090
                                   ▼                                   │
                        ┌────────────────────────┐◀────────────────────┘
                        │ thanos-query (×2)      │  dédoublonne sur prometheus_replica
                        └──┬──────────┬──────────┘
              gRPC 10901   │          │   gRPC 10901
          ┌────────────────┘          └───────────────────┐
          ▼                                               ▼
 prometheus-kps-0 / -1 (sidecar)                 thanos-store (×1)
   base locale 15 j (ceph-rbd)                     cache d'index (ceph-rbd)
          │ envoi des blocs de 2 h                        │ lecture
          ▼                                               ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ RGW ceph-par1 — https://rgw.par1.medisphere.internal          │
   │ compartiment thanos-k8s-par1 (utilisateur RGW thanos, 40 Gio) │
   └──────────────────────────────────────────────────────────────┘
          ▲ compaction, dédoublonnage hors ligne, sous-échantillonnage, rétention
   thanos-compactor (×1, JAMAIS deux)
```

## Faits

| Élément | Valeur |
|---|---|
| Version | Thanos 0.42.4, image `registry.par1.medisphere.internal/quay/thanos/thanos:v0.42.4` (sidecar compris) |
| Étiquettes externes | `cluster="k8s-par1"`, `site="par1"` (values), `prometheus="supervision/kps"`, `prometheus_replica="prometheus-kps-0|1"` (posées par l'opérateur) |
| Étiquette de réplica | `prometheus_replica` (Query : `--query.replica-label`, Compactor : `--deduplication.replica-label`) |
| Rétentions | Prometheus 15 j en local ; compartiment : brut 30 j, 5 min 180 j, 1 h 2 ans (M21-E25) |
| Envois | un bloc de 2 h par réplica, envoyé par le sidecar dès sa fermeture (compaction locale coordonnée : `--storage.tsdb.delay-compact-file.path`, posé par l'opérateur) |
| Flux | sidecars, Store, Compactor → RGW 10.10.30.200:443 (carte `eth1` des travailleurs, M16) ; Query → sidecars et Store en 10901 (espace `supervision`) ; MGMT et `mon01` → 10.10.41.60:9090 |

## Ce qui ne marche plus comme avant sur 10.10.41.60

Thanos Query sert l'API de **requête** de Prometheus (`/api/v1/query`, `query_range`, `series`, `labels`, `rules`, `alerts`, `targets`, `status/buildinfo`), plus `/api/v1/stores`. Il ne sert **pas** `/federate`, `/api/v1/status/config`, `/api/v1/status/flags` de Prometheus, ni l'API d'administration. Pour ceux-là : `kubectl -n supervision port-forward pod/prometheus-kps-0 9090`.

## Lire le compartiment (lecture seule)

```
admin@adm01:~$ (set -a; . ~/.config/workbook/s3-thanos.env; set +a; aws s3 ls s3://thanos-k8s-par1/ | head)
```

Pour `thanos tools bucket ls|inspect|web` depuis `adm01`, le fichier de configuration local est fabriqué par `outils/objstore-local.sh` de `plateforme/observabilite` (RB-214 §2).
