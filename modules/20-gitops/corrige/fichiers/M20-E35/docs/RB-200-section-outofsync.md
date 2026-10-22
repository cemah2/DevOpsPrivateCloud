## L'application reste OutOfSync juste après une synchronisation réussie

> Section ajoutée à RB-200 après INC-4735 (M20-E35). Principe : « OutOfSync persistant » veut dire
> que ce qu'Argo CD **compare** n'est pas ce que le cluster **garde**. On ne masque jamais une
> différence avant d'avoir nommé son auteur.

1. **Photographier** : `outils/argocd-diagnostic.sh <app> --diff` → journal de diagnostic.
2. **Quelles ressources ?** `argocd app get <app>` : colonne `STATUS` = `OutOfSync`.
   - message `ignored (requires pruning)` → branche A ;
   - aucune ressource OutOfSync mais statut `Unknown` + condition `ComparisonError` → branche B ;
   - une ressource OutOfSync qui le redevient après chaque synchro → branche C.
3. **A — élagage refusé** : la ressource n'est plus dans Git mais porte `Prune=false` (ou `Prune=confirm`).
   C'est voulu pour les données. Question à poser : *qui l'a retirée de Git, et pourquoi ?*
   `git log -p -- overlays/<env>` ; remettre la ressource dans Git (revert par MR) **ou**, si sa
   suppression est vraiment décidée (ticket CHG), la supprimer à la main après sauvegarde.
4. **B — génération impossible** : lire le message entier (`argocd app get <app> -o json | jq .status.conditions`).
   `kustomize version … is not registered` : version épinglée dans l'Application/ApplicationSet sans
   `kustomize.path.<version>` dans argocd-cm → retirer l'épinglage (MR) ou déclarer l'outil (Helmfile,
   release argocd). `must specify --enable-helm`, `security; file … is not in or below …` : option
   de construction absente d'Argo CD mais présente en local → aligner la CI sur Argo CD, pas l'inverse.
5. **C — champ réécrit** : `argocd app diff <app>` montre le champ. Comparer avec l'objet vivant et
   ses `managedFields` (`kubectl get … -o yaml --show-managed-fields`) :
   - valeur **équivalente** écrite autrement (quantité `0.25Gi` ↔ `256Mi`, champ par défaut ajouté par
     l'API ou un webhook) → écrire dans Git la forme canonique, sinon `ignoreDifferences` **étroit**
     (un chemin, un objet), ou comparaison côté serveur (`ServerSideDiff=true`, et
     `IncludeMutationWebhook=true` si c'est un webhook) ;
   - valeur **différente** posée par un autre écrivain → ce n'est plus un problème de comparaison :
     voir « La dérive revient ».
6. **Vérifier** : `argocd app get <app> --hard-refresh` → `Synced` ; puis une nouvelle synchro
   automatique ne doit pas rouvrir la différence (attendre une réconciliation, 3 min par défaut).
7. **Prévenir** : la porte de CI de `mediagenda/deploiement` rend les overlays avec la **même version**
   de Kustomize qu'Argo CD (5.8.1 dans Argo CD 3.5) et refuse un overlay qui retire une base CNPG.

Ne jamais : désactiver l'auto-synchronisation « pour que ça se calme » ; poser un `ignoreDifferences`
sur `/spec` entier ; supprimer à la main une ressource `Prune=false` sans ticket.
