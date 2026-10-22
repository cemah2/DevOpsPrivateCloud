<!-- À AJOUTER à docs/kubernetes/reseau/matrice-flux-cluster.md (M21-E07, DEV-2207) -->
| Source | Destination | Port | Politique | Motif | Réf. |
|---|---|---|---|---|---|
| `supervision`, pods `app.kubernetes.io/name=prometheus` | pods des espaces d'équipe (étiquette d'espace `medisphere.internal/equipe`) | TCP 8000 (MédiAgenda), 8080 (MédiDoc), 9187 (CloudNativePG) | CCNP `collecte-prometheus` (`enableDefaultDeny` à faux) | collecte des métriques des applications et des bases | M21-E07 |
