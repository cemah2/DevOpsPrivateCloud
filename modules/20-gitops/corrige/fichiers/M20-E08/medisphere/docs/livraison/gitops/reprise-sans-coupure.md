# Reprendre une charge existante sous Argo CD, sans coupure

| | |
|---|---|
| **Pour** | une application déjà déployée (par `kubectl apply`, un job de CI, Helm) qu'Argo CD doit désormais gérer |
| **Référence** | M20-E08, PLAT-2108 (MédiAgenda dev, 23/10/2026) |
| **Résultat attendu** | l'Application est `Synced`/`Healthy`, **aucun pod recréé**, un seul écrivain |

## 1. Avant : photographier

```
admin@adm01:~$ ns=mediagenda-dev
admin@adm01:~$ kubectl -n $ns get deploy,sts,rs,pods -o wide > ~/m20/e08/avant.txt
admin@adm01:~$ kubectl -n $ns get deploy mediagenda -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}'
admin@adm01:~$ kubectl -n $ns get deploy mediagenda --show-managed-fields -o json | jq '.metadata.managedFields[] | {manager, operation}'
```

Noter : la **révision** du Deployment, le nom du **ReplicaSet** actif (suffixe = empreinte du
modèle de pod), le nom et l'âge des pods, les **gestionnaires de champs** (qui écrit aujourd'hui).

## 2. Un seul écrivain

Retirer d'abord l'ancien chemin d'écriture (ici, le job `deployer-dev` du pipeline de
`mediagenda/deploiement`) et attendre que le dernier pipeline de `main` soit passé **sans** lui.
Deux écrivains sur les mêmes objets, c'est une bataille de dérives assurée.

Vérifier que ce qui tourne correspond à `main` : la dernière exécution de l'ancien chemin a porté
sur le **dernier** commit de `main`. Sinon, le premier `sync` livrera une version : ce n'est plus
une reprise.

## 3. Protéger les données

Sur tout objet qui porte des données (Cluster CNPG, PVC) :
`argocd.argoproj.io/sync-options: Prune=false,Delete=false`, commité AVANT la reprise.

## 4. Créer l'Application SANS synchronisation automatique

Projet de l'équipe, `ServerSideApply=true`, `CreateNamespace=false`, pas de finaliseur
`resources-finalizer`. Elle apparaît `OutOfSync` : c'est normal.

## 5. Lire le diff, objet par objet

```
admin@adm01:~$ argocd app diff mediagenda-dev --server-side-diff
```

**Seules différences acceptables** : l'annotation `argocd.argoproj.io/tracking-id` (Argo CD marque ses
objets) et les annotations ajoutées exprès (étape 3). **Arrêt immédiat** si le diff touche
`spec.template` d'un Deployment ou d'un StatefulSet (image, variables, étiquettes du modèle) : la
synchronisation recréerait les pods.

## 6. Synchroniser à la main, puis vérifier

```
admin@adm01:~$ argocd app sync mediagenda-dev --dry-run
admin@adm01:~$ argocd app sync mediagenda-dev
admin@adm01:~$ kubectl -n $ns get deploy,sts,rs,pods -o wide > ~/m20/e08/apres.txt
admin@adm01:~$ diff <(awk '{print $1}' ~/m20/e08/avant.txt) <(awk '{print $1}' ~/m20/e08/apres.txt)
```

Critère : **même ReplicaSet, mêmes pods, même révision**. Les `managedFields` montrent
`argocd-controller` (`Apply`) à côté de l'ancien gestionnaire : les champs de même valeur sont
co-possédés (normal ; l'ancien gestionnaire est retiré en M20-E30).

## 7. Consigner, puis automatiser

Dans l'Application (`spec.info`) : date de la reprise et révision du Deployment. Puis, par MR,
`automated: {prune: true, selfHeal: true}`.

## Retour arrière

Supprimer l'Application (sans finaliseur, aucun objet n'est supprimé) et réactiver l'ancien chemin.
Les annotations de suivi restées sur les objets sont sans effet hors d'Argo CD.
