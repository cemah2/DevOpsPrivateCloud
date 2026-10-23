<!-- plateforme/medisphere — docs/kubernetes/reseau/matrice-flux-cluster.md (EXTRAIT M29-E14) : lignes à AJOUTER -->
| Source | Destination | Port | Méthode / chemin | Politique | Module |
|---|---|---|---|---|---|
| `k6` / exécuteurs des TestRun (`app: k6`, `runner: "true"`) | `supervision` / Prometheus | 9090 | `POST /api/v1/write` | `prometheus-ecriture-k6` | M29-E14 |
| `k6` (démarreur, opérateur) | `k6` / exécuteurs | 6565 | API REST de k6 | `k6-entree` | M29-E14 |
| `supervision` / Prometheus | `k6` / opérateur | 8443 | `GET /metrics` (HTTP clair malgré le nom du port) | `k6-entree` | M29-E14 |
| `ci-jobs` / jobs de CI | `supervision` / Thanos Query | 9090 | `GET`/`POST /api/v1/query`, `GET /api/v1/query_range` | `thanos-query-lecture-charge` | M29-E14 |
| `k6` / exécuteurs | Gateway `gw-par1` (10.10.41.10) | 443 | HTTPS vers `mediagenda-recette.apps…` | (sortie non restreinte) | M29-E14 |
