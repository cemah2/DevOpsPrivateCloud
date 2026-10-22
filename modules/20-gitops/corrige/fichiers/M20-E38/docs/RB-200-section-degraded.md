## L'application est Degraded (ou Progressing sans fin) après une synchronisation réussie

> Section ajoutée à RB-200 après INC-4738 (M20-E38). « Synced » dit que le cluster ressemble à Git ;
> « Healthy » dit que ce qui a été appliqué fonctionne. Les deux sont indépendants.

1. **Quelle ressource porte la santé ?** `argocd app get <app>` : colonne `HEALTH` ; le message de
   santé (`.status.resources[].health.message`) cite souvent la cause.
2. **Descendre jusqu'au pod**, comme au M14 (RB-145) :
   - `Deployment … Progressing` → `kubectl -n <ns> rollout status deploy/<nom>`, puis les pods
     NEUFS (`kubectl get pods -l … --sort-by=.metadata.creationTimestamp`), leurs événements :
     `ErrImagePull`/`ImagePullBackOff` (digest absent de Harbor, Secret de tirage), `Readiness
     probe failed` (chemin, port, délai), `Pending` + `unbound immediate PersistentVolumeClaims`
     (classe de stockage, quota) ;
   - l'ancienne version reste en service tant que la nouvelle n'est pas prête (rolling update,
     `maxUnavailable: 0`) : ce n'est pas une panne de service, c'est une livraison bloquée ; elle
     devient `Degraded` après `progressDeadlineSeconds` (600 s par défaut).
3. **La santé elle-même peut mentir** : si la ressource « malade » est saine pour son opérateur
   (`kubectl get cluster.postgresql.cnpg.io … -o jsonpath='{.status.phase}'` → `Cluster in healthy
   state`), regarder `resource.customizations.health.*` dans argocd-cm et l'éprouver avec
   `outils/tester-sante.sh` (ou `argocd admin settings resource-overrides health`). Les contrôles
   intégrés d'Argo CD (`resource_customizations/` du projet) couvrent déjà CNPG, cert-manager,
   Argo Rollouts… : ne les remplacer qu'avec une raison écrite.
4. **Corriger dans Git** (revert ou correction par MR) ; un contrôle de santé se corrige dans la
   release Helmfile `argocd`, jamais par `kubectl edit configmap argocd-cm` (la release le
   remettrait, ou pire, le garderait sans trace).
5. **Vérifier** : `argocd app wait <app> --health --timeout 600`.

Ne jamais : supprimer le pod pour « relancer » (le contrôleur recrée le même) ; réduire une sonde
jusqu'à ce qu'elle ne teste plus rien ; ignorer une alerte `health-degraded` de prod parce qu'« elle
ment souvent » — un contrôle faux se corrige, il ne se tolère pas.
