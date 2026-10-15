# Dérive de configuration : la voir, la corriger

*M17-E14 — ticket PLAT-1814. Concerne `k8s-par1`, Helm 4 et Kustomize.*

## Voir une dérive

| Livré par | Commande | Ce qu'elle compare |
|---|---|---|
| Release Helm (dev, plateforme) | `helm diff upgrade <release> <chart> -n <espace> --reuse-values --three-way-merge --context 3` | manifeste de la release, **état réel** et nouveau rendu. Sans `--three-way-merge`, une modification manuelle est invisible |
| Toute la plateforme | `helmfile diff --suppress-secrets --context 3` (même règle : `--three-way-merge` passé par `--diff-args` si besoin) | chaque release du `helmfile.yaml` |
| Overlay Kustomize (recette, prod) | `kubectl diff --server-side -k overlays/<env>` | état réel du cluster et rendu, simulé par le serveur (gestionnaire `kubectl`) |

Code de sortie de `kubectl diff` : 0 = identique, 1 = différences, > 1 = erreur.

## Qui gagne en *server-side apply*

Helm 4 installe en SSA (`apply_method: ssa` dans la release) : chaque champ a un **propriétaire** (`metadata.managedFields`, à lire avec `kubectl get … --show-managed-fields`).
- Un `kubectl edit`, `kubectl patch`, `kubectl set` ou `kubectl apply` côté client **prend** la propriété des champs qu'il modifie (gestionnaire `kubectl-edit`, `kubectl-patch`, `kubectl-client-side-apply`…).
- Le prochain `helm upgrade` qui veut une autre valeur sur ces champs **échoue en conflit**. Il n'écrase rien et n'ignore rien.
- Défaire la modification à la main ne suffit pas : l'ancien propriétaire **copossède** encore le champ, et le conflit reviendra le jour où le chart changera cette valeur.

## Conduite à tenir

1. On ne corrige **jamais** le cluster pour le mettre d'accord avec soi : on corrige le **code** (chart, valeurs, overlay) si la modification manuelle était voulue, sinon on la défait.
2. Correction propre de la propriété :
   - `helm upgrade … --force-conflicts` (Helm reprend le champ), **après** avoir compris d'où vient la modification ;
   - ou retrait de l'entrée `managedFields` du gestionnaire manuel, puis `helm upgrade`.
3. Toujours la **même** commande pour un même dépôt Kustomize (`kubectl apply --server-side -k`, gestionnaire `kubectl`) : jamais de `kubectl apply` côté client, jamais d'autre `--field-manager`. Deux noms font deux propriétaires et des champs fantômes.
4. Le diff à trois voies est collé dans chaque MR (gabarits de MR de `mediagenda/chart` et `mediagenda/deploiement`).
