<!-- À AJOUTER à docs/kubernetes/reseau/matrice-flux-cluster.md (M21-E02, PLAT-2202) -->
| Source | Destination | Port | Politique | Motif | Réf. |
|---|---|---|---|---|---|
| MGMT 10.10.10.0/24, `mon01` 10.10.20.19 | `supervision`, pods `prometheus` (Service LB `prometheus-externe`, 10.10.41.60) | TCP 9090 | CNP `supervision/prometheus-entree` (`fromCIDR`, `externalTrafficPolicy: Local`) | API et interface de Prometheus (exploitation, fédération par le témoin) | M21-E02 |
| MGMT, `mon01` | `supervision`, pods `alertmanager` (Service LB `alertmanager-externe`, 10.10.41.61) | TCP 9093 | CNP `supervision/alertmanager-entree` | API d'Alertmanager (amtool, silences, sondes du témoin) | M21-E02 |
| espace `supervision` (Grafana, Prometheus) | pods `prometheus` / `alertmanager` | TCP 9090, 9093, 8080 | mêmes CNP (`fromEndpoints`) | source de données de Grafana, envoi des alertes, auto-collecte (rechargeur 8080) | M21-E02 |
| Gateway `gw-par1` (identité `ingress`) | `supervision`, pod Grafana | TCP 3000 | aucune politique sur Grafana (espace sans refus par défaut) | interface de Grafana par HTTPRoute | M21-E02 |
