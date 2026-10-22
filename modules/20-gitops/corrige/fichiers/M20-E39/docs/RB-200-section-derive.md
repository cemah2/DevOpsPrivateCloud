## La dérive revient sans cesse (synchronisations automatiques en boucle)

> Section ajoutée à RB-200 après INC-4739 (M20-E39). `selfHeal` répare une dérive ; il ne
> répare pas un **second écrivain**. Deux contrôleurs qui veulent deux valeurs différentes pour le
> même champ se battent indéfiniment (Argo CD espace ses réparations : 2 s, 6 s, 18 s… jusqu'à
> 5 min, `controller.self.heal.backoff.*`), et chaque réparation peut redémarrer des pods.

1. **Constater la bataille** : historique (`argocd app history <app>` : synchronisations
   automatiques rapprochées sans nouveau commit), événements de l'objet
   (`kubectl get events --field-selector involvedObject.name=<nom>`), générations successives.
2. **Nommer l'autre écrivain** : `outils/qui-ecrit.sh <ns> <type> <nom>`.
   | Indice | Écrivain | Correctif durable |
   |---|---|---|
   | sous-ressource `scale`, manager `kube-controller-manager`, HPA présent | HPA contre `replicas` de Git | retirer `replicas` du rendu de Git **ou** l'ignorer (`ignoreDifferences` sur `/spec/replicas` + `RespectIgnoreDifferences=true`) ; jamais les deux écrivains |
   | condition `SharedResourceWarning`, annotation de suivi qui change de propriétaire | deux Applications | une seule Application par objet ; supprimer l'intruse **sans cascade** (vérifier ses finaliseurs) ; `FailOnSharedResource=true` en prévention |
   | manager inconnu (`curl`, nom d'outil), RoleBinding vers un compte d'un autre espace | script ou tâche planifiée | arrêter l'écrivain (supprimer la tâche, révoquer ses droits), porter le besoin dans Git (la valeur voulue, par MR) |
3. **Ne pas désactiver selfHeal** pour « calmer » : la dérive resterait, invisible.
4. **Vérifier** : une observation de quelques minutes sans synchronisation automatique ni nouvelle
   génération (`lab/bin/check 20 39`).
5. **Prévenir** : plus aucun gestionnaire de champs autre qu'Argo CD sur les objets applicatifs
   (M20-E30) ; orphelins signalés par les AppProjects ; droits d'écriture dans les espaces
   applicatifs réservés à Argo CD.
