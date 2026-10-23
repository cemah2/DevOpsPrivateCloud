<!-- plateforme/medisphere — docs/plateforme-dev/portail.md : section AJOUTÉE en M28-E10 (DEV-2910). -->

## Plugins d'état

### Kubernetes

| Élément | Valeur |
|---|---|
| Cluster | `k8s-par1`, client « dans le cluster » (compte de service `portail/portail`, `authProvider: serviceAccount` sans jeton) |
| Droits | ClusterRole `portail-lecture-k8s` : lecture des pods, Services, Deployments, ReplicaSets, StatefulSets, DaemonSets, HPA, Jobs, CronJobs, Ingress, LimitRanges, ResourceQuotas, Rollouts, métriques des pods. **Ni Secrets, ni ConfigMaps, ni journaux**, aucun verbe d'écriture |
| Rattachement | annotation `backstage.io/kubernetes-id` de l'entité = étiquette des objets (posée par `labels` de la base Kustomize de chaque dépôt de déploiement, hors sélecteurs) |
| Exposé à | toute personne connectée au portail : noms, états, redémarrages, images, réplicas — rien de plus que ce qu'un `view` donnerait, sans les ConfigMaps |
| Interdit | suppression de pod depuis le portail (`kubernetes.frontend.podDelete.enabled: false`) |

### TechDocs

| Élément | Valeur |
|---|---|
| Construction | par la CI de chaque projet (`techdocs-cli generate --no-docker`, image `plateforme/outils-techdocs`), à chaque fusion sur `main` qui touche `docs/` ou `mkdocs.yml` |
| Publication | `s3-01`, compartiment `portail-techdocs`, chemin `default/component/<nom>/` ; identité `techdocs-ecriture` (CI) |
| Lecture | le portail, identité `techdocs-lecture` (`kv/plateforme/portail`) ; `techdocs.builder: external` : le portail ne construit rien |
| Entité | annotation `backstage.io/techdocs-ref: dir:.` |
