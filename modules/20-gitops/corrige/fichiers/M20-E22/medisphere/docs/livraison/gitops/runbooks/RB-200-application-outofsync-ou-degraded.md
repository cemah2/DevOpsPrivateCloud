# RB-200 — Une application est `OutOfSync` ou `Degraded`

| | |
|---|---|
| **Déclencheurs** | courriel « [Argo CD] Échec de synchronisation » ou « Application dégradée » (M20-E19) ; tuile rouge ou jaune dans `https://argocd.apps.par1.medisphere.internal` ; ticket d'une équipe |
| **Gravité** | prod `Degraded` : incident (INC), astreinte. Prod `OutOfSync` seul : normal entre une fusion et la synchronisation manuelle ; anormal s'il dure ou si personne n'a fusionné. dev/recette : heures ouvrées |
| **Accès** | `argocd` (compte personnel), `kubectl` (identité personnelle), `kubectl argo rollouts` ; lecture seule tant que le diagnostic n'est pas posé |
| **Propriétaire** | équipe Plateforme. Relu par Nadia Roussel (support) et Julien Petit (MédiAgenda) |

> ⚠️ **Règle d'or.** On ne corrige **pas** le cluster à la main : Argo CD le remettrait (auto-réparation)
> ou, pire, la correction disparaîtrait à la synchronisation suivante. On corrige **Git** (MR), ou on
> agit sur Argo CD lui-même (refresh, sync, terminate-op). Exception : l'urgence de prod, tracée (§6).

## 1. Qualifier en 2 minutes

```
argocd app get <APP> --refresh            # statut de synchro, santé, conditions, dernière opération
argocd app list -l medisphere.internal/equipe=<EQUIPE>
```

Lis **trois** choses, dans cet ordre :

| Ce que tu vois | Ce que ça veut dire | Aller à |
|---|---|---|
| `Conditions` contient `ComparisonError` | Argo CD n'arrive même pas à calculer l'état voulu (dépôt, rendu, projet) | §2 |
| `Sync Status: OutOfSync`, opération `Succeeded` ou aucune | le cluster diffère de Git : dérive, fusion pas encore synchronisée, champ réécrit par un tiers | §3 |
| `Operation: Sync … Failed` / `Error` | la dernière synchronisation a échoué | §4 |
| `Health: Degraded` (ou `Progressing` qui dure, `Missing`, `Suspended`) | les objets sont appliqués mais ne fonctionnent pas | §5 |

`Unknown` sur toutes les Applications d'un cluster : c'est le cluster qui est injoignable (secret de cluster,
réseau), pas l'application — voir RB-20x (cluster distant).

## 2. `ComparisonError` : Argo CD ne sait pas rendre l'application

```
argocd app get <APP> -o json | jq '.status.conditions'
argocd repo list                                       # état de connexion de chaque dépôt
argocd app manifests <APP> --source git | head         # le rendu passe-t-il ?
kubectl -n argocd logs deploy/argocd-repo-server --since=15m | grep -i error
```

| Message typique | Cause probable | Action |
|---|---|---|
| `authentication required`, `403` | jeton de déploiement expiré ou révoqué | nouveau jeton (GitLab), Vault, `secrets-k8s.sh appliquer argocd` |
| `x509: certificate signed by unknown authority` | racine MédiSphère absente d'`argocd-tls-certs-cm` pour ce nom d'hôte | valeur `configs.tls.certificates` (Helmfile `argocd`) |
| `kustomize build … failed`, `helm template … failed` | erreur de rendu commitée | relire le dernier commit du dossier ; `kubectl kustomize` en local ; revert par MR |
| `application repo … is not permitted in project` | dépôt ou destination hors de l'AppProject | corriger l'Application ou l'AppProject (MR `plateforme/gitops`), jamais « passer en `default` » |
| `i/o timeout` vers `git01` ou `registry` | réseau du repo-server (politique, bordure) | CiliumNetworkPolicy de l'espace `argocd` (M20-E25), matrice des flux |

## 3. `OutOfSync` : le cluster diffère de Git

```
argocd app diff <APP>                                   # QUOI diffère (champ par champ)
argocd app get <APP> -o json | jq '.status.resources[] | select(.status == "OutOfSync") | {kind, name, namespace}'
kubectl get <TYPE> <NOM> -n <ESPACE> --show-managed-fields -o yaml | yq '.metadata.managedFields[] | {manager, operation, time}'
```

Les `managedFields` disent **qui** a écrit le champ : `argocd-controller` (Argo CD), `kubectl…` (un
humain), `kube-controller-manager` (HPA), `rollouts-controller` (Argo Rollouts), un opérateur…

| Constat | Cause | Action |
|---|---|---|
| un humain a modifié l'objet (`kubectl-edit`, `kubectl-client-side-apply`) | dérive manuelle | si `selfHeal` : Argo CD a déjà remis ou va remettre. Sinon : `argocd app sync <APP>` (après accord en prod). Retrouver l'auteur (journal d'audit de l'API, M14-E27) |
| un contrôleur réécrit sans cesse un champ (réplicas par un HPA, poids d'HTTPRoute par Argo Rollouts, valeurs par défaut d'un webhook) | conflit de propriétaires | `ignoreDifferences` **ciblé** (groupe, type, nom, champ) + `RespectIgnoreDifferences=true` ; diff côté serveur avec `IncludeMutationWebhook=true` pour les webhooks (M20-E12) |
| la ressource est en trop (`requires pruning`) | objet retiré de Git, `prune` désactivé (prod) | vérifier qu'il doit disparaître, puis `argocd app sync <APP> --prune` ; ConfigMap générée ancienne : annotation `IgnoreExtraneous` (M20-E12) |
| la ressource manque (`Missing`) | jamais créée : synchro manuelle non faite, ou refusée | §4 |
| `mediagenda-prod` OutOfSync juste après une fusion | normal : synchro manuelle | `argocd app diff`, puis `argocd app sync mediagenda-prod` par la personne de garde du changement |
| OutOfSync qui revient après chaque synchro | deux écrivains : deux Applications sur le même objet, un CronJob, un opérateur | lister les propriétaires (`managedFields`, annotation `argocd.argoproj.io/tracking-id`) ; un seul propriétaire par champ |

## 4. La synchronisation échoue

```
argocd app get <APP> -o json | jq '.status.operationState | {phase, message, syncResult: [.syncResult.resources[]? | select(.status != "Synced") | {kind, name, status, message, hookPhase}]}'
argocd app history <APP>
kubectl get events -n <ESPACE> --sort-by=.lastTimestamp | tail -20
```

| Message | Cause | Action |
|---|---|---|
| `admission webhook … denied`, `violates PodSecurity` | objet refusé par l'admission (VAP `medisphere-images`, PSA) | corriger le manifeste (MR) |
| `exceeded quota` | quota de l'espace | revoir requêtes/limites ou le quota (MR `plateforme/k8s`) |
| `resource … is not permitted in project` | type interdit par l'AppProject (ResourceQuota, objets de cluster…) | l'objet relève de la plateforme : le déplacer dans `plateforme/k8s` |
| hook `mediagenda-migrate` en `Failed` | migration de schéma en échec | `kubectl logs job/mediagenda-migrate -n <ESPACE>` ; **ne pas** relancer en boucle ; corriger la migration (nouvelle version) ; la version en place continue de servir (le Deployment n'a pas été touché) |
| `metadata.annotations: Too long` | CRD trop grosse pour l'apply côté client | `ServerSideApply=true` |
| opération bloquée en `Running` | hook ou vague qui n'atteint jamais `Healthy` | `argocd app terminate-op <APP>`, puis traiter l'objet bloqué |

Après correction dans Git : `argocd app sync <APP>` (ou attendre l'auto-synchro, `retry` compris).

## 5. `Degraded` : appliqué mais malade

```
argocd app get <APP> -o json | jq '.status.resources[] | select(.health.status != "Healthy" and .health != null) | {kind, name, health}'
kubectl get pods -n <ESPACE> ; kubectl describe pod <POD> -n <ESPACE> ; kubectl logs <POD> -n <ESPACE> --previous
kubectl argo rollouts get rollout <ROLLOUT> -n <ESPACE>       # si l'application a un Rollout
```

| Objet dégradé | Pistes |
|---|---|
| Deployment / ReplicaSet | image introuvable (`ErrImagePull` : digest promu inexistant ?), sonde mal réglée, crash au démarrage, secret absent (`CreateContainerConfigError`) — RB-14x pour les pods |
| Rollout `Degraded` | canary **interrompu** par une analyse (`kubectl argo rollouts get` : AnalysisRun `Failed`/`Error`) : c'est le garde-fou qui a joué. La version stable sert toujours. Lire l'AnalysisRun, corriger, promouvoir une nouvelle version. `kubectl argo rollouts retry` seulement si la cause était passagère |
| Rollout `Suspended` (santé `Suspended`) | pause de canary en attente de promotion : normal en prod (dernière marche manuelle) |
| Cluster CNPG | `kubectl cnpg status <CLUSTER> -n <ESPACE>` — RB-16x |
| PVC `Pending` | classe de stockage, quota de stockage, ceph-csi — RB-16x |
| HTTPRoute | `kubectl describe httproute` : `Accepted`/`ResolvedRefs` (Service absent, mauvais port) |

## 6. Urgence en prod

Si la prod sert des erreurs et que la cause est la dernière version :
1. `kubectl argo rollouts abort mediagenda -n mediagenda-prod` si un canary est en cours (retour immédiat
   du trafic sur la version stable) ;
2. sinon, **revert par MR** de la promotion (`git revert -m 1 <FUSION>`), fusion par un Maintainer,
   `argocd app sync mediagenda-prod` : la fenêtre de retour arrière du Rollout le rend immédiat ;
3. `argocd app rollback` seulement si Git est indisponible : il exige de couper la synchro automatique
   et laisse l'application OutOfSync ; ouvrir aussitôt la MR qui remet Git en accord.

## 7. Clore

- l'application est `Synced` et `Healthy` (`argocd app wait <APP> --health --sync --timeout 300`) ;
- la cause est corrigée **dans Git** (lien de la MR) ;
- journal dans `docs/kubernetes/journal/` ; post-mortem si prod touchée plus de 15 min ou données en jeu.
