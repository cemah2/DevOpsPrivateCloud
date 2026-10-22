# Sous le capot : du commit à l'objet (M20-E44, PLAT-2144)

> EXEMPLE de livrable rempli. Les horodatages, empreintes et durées sont représentatifs : les tiens
> diffèrent. Mesures prises le 6 novembre sur mediagenda-dev, Argo CD 3.5.5, webhook actif (E27).

## Chronologie mesurée d'une livraison en dev

| Étape | Horodatage | Source de la mesure | Écart |
|---|---|---|---|
| Commit de la MR | 10:14:02 | API GitLab, `committed_date` | — |
| Fusion de la MR | 10:16:41 | API GitLab, `merged_at` | 2 min 39 (pipeline de MR) |
| Webhook reçu | 10:16:42 | `argocd-server` : `Received push event repo: …/mediagenda/deploiement, revision: 9b0d…, touchedHead: true` | 1 s |
| Rafraîchissement | 10:16:42 | contrôleur : `Refreshing app status (controller refresh requested), level (3)` | < 1 s |
| Manifestes générés | 10:16:44 | repo-server (debug) : `git fetch`, `kustomize build`, `manifest.cache.miss` puis écriture `mfst|…` | 2 s |
| Début de l'opération | 10:16:45 | `.status.operationState.startedAt` (automatique) | 1 s |
| Fin de l'opération | 10:17:31 | `.status.operationState.finishedAt` (vagues -3, -2, -1 avec le Job de migration, 0) | 46 s |
| Pod neuf créé | 10:17:29 | `kubectl get pods --sort-by=.metadata.creationTimestamp` | — |
| Pod neuf prêt | 10:17:52 | condition `Ready` | 23 s (sonde `/pret`) |

Sans webhook (`argocd-webhook` désactivé le temps de la mesure) : fusion à 10:42:10, rafraîchissement
à 10:44:57 (interrogation périodique : `timeout.reconciliation` 180 s + gigue), soit 2 min 47 de plus.

## Le repo-server et son cache

- Copies de travail : `kubectl -n argocd exec deploy/argocd-repo-server -- ls /tmp/_argocd-repo/`
  → un répertoire par dépôt, nommé par un UUID (le chemin n'apparaît jamais en clair dans les
  journaux pour ne pas fuiter l'URL avec identifiants).
- Cache des manifestes dans Redis, clé `mfst|<suivi>|<application>|<révision>|<espace>|<empreinte
  de la source>…` : une même révision n'est rendue qu'une fois ; `reposerver.repo.cache.expiration`
  (24 h par défaut). Les révisions résolues d'une branche (`git ls-remote`) sont gardées sous
  `git-refs|<dépôt>` quelques minutes : c'est pourquoi un dépôt devenu illisible peut sembler
  fonctionner encore un moment, et pourquoi `--hard-refresh` accélère un diagnostic.

## Redis

- Rôle : cache partagé (manifestes, révisions, détails d'applications, état des ressources pour
  l'interface). Pas de donnée de référence : sa perte coûte des recalculs, pas des déploiements.
- Clés relevées (familles) : `mfst|`, `git-refs|`, `appdetails|`, `revisionmetadata|`,
  `app|managed-resources|…`, `cluster|info|…` ; lues par
  `redis-cli -a "$REDIS_PASSWORD" --no-auth-warning --scan --count 200 | cut -d'|' -f1 | sort | uniq -c`.

## Le contrôleur d'applications

- Déclencheurs : webhook (via l'API), événement d'un objet surveillé, période de réconciliation
  (180 s, `timeout.reconciliation`) ; niveaux de comparaison 0 à 3 dans les journaux (`level (3)` =
  régénérer depuis Git).
- Cache d'état : le contrôleur surveille (watch) tous les types de ressources des clusters gérés et
  garde l'état en mémoire ; une comparaison ne réinterroge pas l'API. Mesure : 2 300 objets suivis,
  `argocd_cluster_api_resource_objects`.
- Journal en debug : `Reconciliation completed` avec `time_ms=212`, `comparison-level=3`,
  `git_ms=…`, `compare_app_state_ms=…` ; puis `Initialized new operation` et
  `updated 'argocd/mediagenda-dev' operation (phase: Succeeded)`.

## Comparaison (diff)

- Stratégie : comparaison côté serveur — annotation
  `argocd.argoproj.io/compare-options: ServerSideDiff=true,IncludeMutationWebhook=true` posée par
  l'ApplicationSet (M20-E12) ; `controller.diff.server.side` absent d'argocd-cmd-params-cm.
- `argocd app manifests mediagenda-dev --source git > argo.yaml` et `kubectl kustomize overlays/dev
  > local.yaml` : mêmes objets ; seule différence, l'annotation de suivi qu'Argo CD ajoute au rendu.

## Annotation de suivi

- `mediagenda-dev:apps/Deployment:mediagenda-dev/mediagenda` (application, groupe/type, espace/nom).
- Retirée à la main : l'objet apparaît « non suivi » puis la synchro automatique la remet. Copiée
  sur un objet étranger : Argo CD le considère comme sien et l'élaguerait s'il n'est pas dans Git.

## Ce que j'en retiens pour l'exploitation

- Métriques (M21) : `argocd_app_reconcile` (durée), `argocd_git_request_total` par type,
  `argocd_app_sync_total{phase="Failed"}`.
- Réglages : webhook obligatoire sur les dépôts suivis ; `reposerver.parallelism.limit` à surveiller
  quand les ApplicationSets grossiront.
