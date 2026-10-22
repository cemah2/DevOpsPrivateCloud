## La synchronisation échoue (Sync failed)

> Section ajoutée à RB-200 après INC-4736 (M20-E36). Une synchronisation en échec n'applique RIEN
> de la vague en cause : l'application garde la version précédente. Ce n'est pas une panne de
> production en soi, c'est une livraison bloquée — à traiter vite, jamais par la force.

1. **Lire le message de l'opération**, pas seulement le statut :
   `argocd app get <app> --show-operation` ou `outils/argocd-diagnostic.sh <app>` (bloc « opération »
   et ressources en échec). Le message cite l'objet et la règle.
2. **Classer** :
   | Message | Étage | Correctif |
   |---|---|---|
   | `… is invalid: spec.selector … field is immutable` | API (validation) | revenir au sélecteur d'origine (revert) ; un vrai changement de sélecteur = nouvel objet (nom différent) puis retrait de l'ancien, planifié |
   | `resource <groupe>:<Kind> is not permitted in project <p>` | AppProject | la ressource n'a rien à faire dans le dépôt de l'équipe : la porter par la plateforme (plateforme/k8s ou plateforme/gitops) ; jamais élargir le projet pour « faire passer » |
   | `PreSync hook failed`, Job `BackoffLimitExceeded` | hook | journaux du Job (`kubectl logs job/<nom>`), corriger le hook ou le retirer ; vérifier `hook-delete-policy` |
   | `exceeded quota: …` | admission (ResourceQuota) | le besoin est-il légitime ? sinon revert ; si oui, ticket à la plateforme pour le quota (code de plateforme/k8s) |
   | `admission webhook … denied`, `ValidatingAdmissionPolicy … denied` | admission | la politique a raison jusqu'à preuve du contraire |
3. **Corriger dans Git** (MR de revert ou de correction), puis observer la synchronisation
   automatique suivante. Une synchro en échec n'est pas relancée automatiquement pour la même
   révision (sauf `retry`) : `argocd app sync <app>` après le correctif si besoin, jamais `--force`
   ni `--replace` sans comprendre ce qu'ils suppriment.
4. **Expliquer pourquoi la CI ne l'a pas vu** : kubeconform valide un schéma, pas l'immutabilité, les
   AppProjects, les quotas ni les webhooks. Porte complémentaire : `outils/verifier-overlay.sh`
   (job `verifier-overlays`) et, pour les cas restants, la comparaison côté serveur d'Argo CD
   (les webhooks de validation s'expriment dès le diff).

Ne jamais : désactiver l'auto-synchronisation de dev pour « débloquer » ; ajouter `Replace=true`
ou `Force=true` pour contourner un champ immuable (suppression puis recréation de l'objet).
