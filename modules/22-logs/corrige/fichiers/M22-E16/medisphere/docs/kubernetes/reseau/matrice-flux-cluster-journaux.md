<!-- Section à ajouter à docs/kubernetes/reseau/matrice-flux-cluster.md (M22-E16, SEC-2316) -->

## Espace `journaux` (Loki, Alloy)

| # | Source | Destination | Port | Niveau 7 | Politique | Justification |
|---|---|---|---|---|---|---|
| J1 | Alloy (`journaux`, DaemonSet) | `loki-0` | 3100/TCP | `POST /loki/api/v1/push` | `loki-entree` | Collecte des pods, nœuds, audit, événements |
| J2 | Grafana (`supervision`) | `loki-0` | 3100/TCP | `GET /loki/api/v1/*`, `POST` requêtes, `GET /ready`, règles du *ruler* | `loki-entree` | Sources par locataire |
| J3 | Prometheus (`supervision`) | `loki-0` | 3100/TCP | `GET /metrics` | `loki-entree` | Supervision de Loki |
| J4 | VMs du lab (INFRA 10.10.20.0/24, DMZ 10.10.70.0/24, `gw01`/`gw02` 10.10.40.2-3) par 10.10.41.62 | `loki-0` | 3100/TCP | `POST /loki/api/v1/push` | `loki-entree` | Journaux des VMs (journald) |
| J5 | MGMT 10.10.10.0/24 (`adm01`) | `loki-0` | 3100/TCP | aucun filtre | `loki-entree` | Administration, checks, `logcli`, effacement (RB-221) |
| J6 | Entité `host` (kubelet) | `loki-0` | 3100/TCP | — | `loki-entree` | Sondes |
| J7 | `loki-0` | `loki-0` | 9095, 7946, 3100/TCP | — | `loki-entree`, `loki-sortie` | gRPC interne, memberlist |
| J8 | `loki-0` | CoreDNS (`kube-system`) | 53/UDP+TCP | — | `loki-sortie` | Résolution |
| J9 | `loki-0` | RGW 10.10.30.200 (par `eth1`) | 443/TCP | — | `loki-sortie` | Chunks, index, règles, demandes d'effacement |
| J10 | `loki-0` | Alertmanager (`supervision`) | 9093/TCP | — | `loki-sortie` | Alertes du *ruler* |
| J11 | `loki-0` (conteneur `loki-sc-rules`) | API Kubernetes | 6443/TCP | — | `loki-sortie` | Lecture des ConfigMaps de règles |

Refusé (vérifié en M22-E16) : tout pod d'un autre espace vers `loki-0` ; toute lecture depuis les VMs. Reste falsifiable : l'en-tête `X-Scope-OrgID` depuis Grafana et depuis MGMT (M24 : passerelle authentifiante).
