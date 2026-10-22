## Une synchronisation a supprimé des ressources (élagage)

> Section ajoutée à RB-200 après INC-4741 (M20-E41). Avec `prune: true`, **Git est la liste
> exhaustive** de ce qui doit exister : tout objet suivi qui disparaît du rendu est supprimé du
> cluster. Un fichier déplacé, renommé ou oublié dans une liste `resources:`/`components:` = une
> suppression, sans autre avertissement que le diff de la MR.

1. **Quoi, quand, par quel commit** : `argocd app history <app>` (révision de la synchro), puis
   `argocd app get <app> --show-operation` ou `.status.operationState.syncResult.resources[]`
   (`message: pruned`). Dans le dépôt : `git show <révision> --stat`, `git log -p -- overlays/<env>`.
   Le rendu avant/après : `kubectl kustomize` sur les deux révisions (ou `outils/verifier-overlay.sh`).
2. **Rétablir par Git** : `git revert` du commit fautif, MR, fusion ; Argo CD recrée les objets
   (même nom, même contenu). Jamais `kubectl apply` à la main : la synchro suivante les ré-élaguerait.
3. **Évaluer les dégâts** : objets sans état (Service, NetworkPolicy, Deployment) → recréés à
   l'identique ; objets porteurs de données → **ne devraient pas pouvoir** être élagués
   (`Prune=false`) ; si c'est arrivé : procédure de restauration (CNPG, Velero, M16) et ticket INC P1.
4. **Prévenir** :
   - `Prune=false,Delete=false` sur tout ce qui porte des données, posé par un component
     (`components/protection-donnees`) plutôt qu'à la main fichier par fichier ;
   - `PruneLast=true` dans l'ApplicationSet : l'élagage passe après l'application et la santé du
     reste (un objet renommé n'est supprimé qu'une fois le nouveau en place) ;
   - `Prune=confirm` sur ce dont la suppression doit rester une décision humaine (Namespace, bases
     partagées) : la synchronisation s'arrête et attend une confirmation ;
   - **prod sans synchronisation automatique** (ni prune automatique) : un élagage en prod se voit
     dans le diff de `argocd app sync --dry-run`/`argocd app diff`, avant d'être confirmé ;
   - porte de MR : `outils/verifier-overlay.sh` affiche « objets qui DISPARAISSENT » et refuse
     ceux qui portent des données.

Ne jamais : supprimer une Application « pour repartir propre » sans vérifier ses finaliseurs
(`resources-finalizer.argocd.argoproj.io` = suppression en cascade de tout ce qu'elle gère).
