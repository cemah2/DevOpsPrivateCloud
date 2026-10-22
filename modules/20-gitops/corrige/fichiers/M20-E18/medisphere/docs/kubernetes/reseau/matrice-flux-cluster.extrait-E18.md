<!-- plateforme/medisphere — docs/kubernetes/reseau/matrice-flux-cluster.md : lignes AJOUTÉES en M20-E18
     (DEV-2118), section des applications. Mêmes colonnes que la matrice du M15-E32. -->

| Source | Destination | Proto/port | Chiffré | Besoin | Autorisé par | Origine |
|---|---|---|---|---|---|---|
| contrôleur Argo Rollouts (`argo-rollouts`, `app.kubernetes.io/name: argo-rollouts`) | API MédiAgenda, pods canary (`mediagenda-recette`, `mediagenda-prod`), via le Service `mediagenda-canary` | TCP 8000 (`http`) | non (dans le cluster) | mesures `web` de l'analyse `pret-mediagenda` | `mediagenda-analyses-entree` (NetworkPolicy, component `canary`) | M20-E18 |
| Job de fumée (`medisphere.internal/role: analyse`, même espace) | API MédiAgenda, via `mediagenda-canary` | TCP 8000 | non | analyse `fumee-mediagenda` | `mediagenda-analyses-entree` (entrée), `mediagenda-analyses-sortie` (sortie) | M20-E18 |
| Job de fumée | CoreDNS (`kube-system`) | UDP/TCP 53 | non | résolution du Service canary | `mediagenda-analyses-sortie` | M20-E18 |
| contrôleur Argo Rollouts | API Kubernetes (VIP) | TCP 443/6443 | TLS | Rollouts, HTTPRoute (greffon), Jobs d'analyse | aucune politique sur `argo-rollouts` (sortie libre dans le cluster) ; M20-E25 pourra la restreindre | M20-E15 |
| contrôleur Argo Rollouts | `labo-apercu` (`wb-essais`) | TCP 8080 | non | analyse d'aperçu `pret-http` (blue/green de labo) | aucune politique d'entrée sur les pods de `labo` (sinon : en ajouter une, comme pour MédiAgenda) | M20-E17 |
