# AAAA-MM-JJ — F2-S06 : la recette de MédiVisio ne déploie plus sa nouvelle version (DEV-3206)

> Journal de diagnostic de la solution de référence, écrit pour la **variante 1** (quota). Les variantes 2 et 3 sont traitées dans le corrigé ; ton journal décrit celle que tu as rencontrée.

## Symptôme rapporté

Inès Garnier, HH:MM : « notre déploiement en recette ne démarre pas, ça marchait en dev ; Argo CD dit synchronisé ».

## Diagnostic

| Heure | Commande | Ce qu'elle apprend |
|---|---|---|
| HH:MM | `argocd app get medivisio-consultation-recette` | `Synced`, santé `Progressing` depuis 40 min : Git est appliqué, le déploiement ne finit pas |
| HH:MM | `kubectl -n medivisio-recette get deploy,rs -l app.kubernetes.io/instance=consultation` | nouveau ReplicaSet : 3 désirés, 1 créé ; l'ancien garde 2 pods (le service répond encore en ancienne version) |
| HH:MM | `kubectl -n medivisio-recette describe rs consultation-<hash>` | `ReplicaFailure` : `pods "…" is forbidden: exceeded quota: quota, requested: requests.memory=448Mi, used: requests.memory=576Mi, limited: requests.memory=768Mi` |
| HH:MM | `git log -p overlays/recette/kustomization.yaml` (`medivisio/consultation-deploiement`) | commit de la veille : 3 réplicas et 448 Mi par pod « pour la démonstration » |

## Cause

L'overlay de recette demande 3 × 448 Mi = 1 344 Mi de *requests* mémoire ; le quota de `medivisio-recette` en accorde 768 Mi (fichier d'équipe, S02). Pendant la mise à jour progressive, le premier nouveau pod passe (448 + 2 × 64 = 576 Mi), le deuxième est refusé : le déploiement reste à mi-chemin. Argo CD, lui, a bien appliqué Git : il n'a aucune raison de signaler une erreur de synchronisation.

## Correction

MR `fix(recette): revenir à 2 réplicas de 64 Mi` (revert du commit) dans `medivisio/consultation-deploiement`, fusionnée par Inès ; synchronisation automatique ; rollout terminé en 1 min ; `/sante` 200.

## Réponse à Inès

« La modification d'hier demandait plus de mémoire que le quota de votre recette. La recette tourne de nouveau. Si la démonstration a vraiment besoin de 3 réplicas plus gros, on ouvre une MR sur `equipes/medivisio.yaml` (quota de recette) : la CI vérifiera que les travailleurs peuvent le tenir. »

## Prévention

- Contrôle en CI du dépôt de déploiement (RB-321, § Prévention).
- RB-321 publié ; tableau de bord de l'équipe : panneau « quota utilisé / quota » par espace.
