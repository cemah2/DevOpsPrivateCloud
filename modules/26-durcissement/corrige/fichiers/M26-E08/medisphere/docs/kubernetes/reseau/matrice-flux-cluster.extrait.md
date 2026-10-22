<!-- À INTÉGRER dans plateforme/medisphere — docs/kubernetes/reseau/matrice-flux-cluster.md, M26-E08 (SEC-2708). -->

| Source | Destination | Port | Protocole | Pourquoi | Politique | Depuis |
|---|---|---|---|---|---|---|
| `falco` / falcosidekick | `journaux` / Loki | 3100 | HTTP, `POST /loki/api/v1/push` seulement | événements Falco → locataire `audit` | `loki-entree` (plateforme/observabilite) | M26-E08 |
| `falco` / falcosidekick | `supervision` / Alertmanager `kps` | 9093 | HTTP, API v2 | alertes Falco de priorité ≥ warning | `alertmanager-entree` (plateforme/observabilite) | M26-E08 |
| `falco` / pods `falco` | `falco` / falcosidekick | 2801 | HTTP | `http_output` de Falco | aucune (même espace, pas de refus par défaut) | M26-E08 |
| `supervision` / Prometheus | `falco` / falcosidekick | 2801 | HTTP, `/metrics` | métriques `falcosecurity_falcosidekick_*` | aucune | M26-E08 |
| `supervision` / Prometheus | `kyverno` / contrôleurs | 8000 | HTTP, `/metrics` | métriques de Kyverno | aucune | M26-E07 |
| kube-apiserver (nœuds de contrôle) | `kyverno` / `kyverno-svc` | 443 → 9443 | HTTPS | webhooks d'admission | aucune (l'API joint le Service depuis le réseau des nœuds) | M26-E07 |
