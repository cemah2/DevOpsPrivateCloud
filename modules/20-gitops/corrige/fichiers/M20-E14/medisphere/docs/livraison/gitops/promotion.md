# Promotion de MédiAgenda entre environnements

> Exemple de livrable (M20-E14, PLAT-2114). Propriétaire : équipe Plateforme. Relu par Julien Petit
> (équipe MédiAgenda) et Karim Benali. Dernière revue : <DATE>.

## Principe

Une version de MédiAgenda est un **digest d'image** signé par la clé MédiSphère, construit une seule
fois par la CI (`mediagenda/api`, étiquette `vX.Y.Z`). Promouvoir, c'est recopier **ce digest** (et la
version lisible qui l'accompagne) d'un overlay de `mediagenda/deploiement` au suivant, **par MR**.
Rien n'est reconstruit, rien n'est ré-étiqueté. Argo CD applique ce que dit `main`.

```
mediagenda/api (étiquette vX.Y.Z) ── CI : construit, analyse, signe, pousse ──► Harbor medisphere@sha256:…
        │
        └─ MR automatique (compte ci-promotion, M19-E17) ──► overlays/dev ──► Argo CD : mediagenda-dev (auto)
                                                                   │
           outils/promouvoir.sh dev recette ── MR ── fusion ──► overlays/recette ──► mediagenda-recette (auto, canary)
                                                                   │
           outils/promouvoir.sh recette prod ── MR ── fusion ──► overlays/prod ──► mediagenda-prod (synchro MANUELLE, canary)
```

## Qui fait quoi

| Étape | Qui | Comment | Garde-fou |
|---|---|---|---|
| dev | la CI | MR ouverte par `ci-promotion` à l'étiquette `vX.Y.Z` de `mediagenda/api` | pipeline de MR de `deploiement` : rendu, schémas, signature (M19-E29) |
| dev → recette | un membre de l'équipe MédiAgenda ou de la Plateforme | `outils/promouvoir.sh dev recette` | fusion par un Maintainer (Julien Petit, Karim Benali) ; synchro automatique ; canary et analyses (M20-E16, E18) |
| recette → prod | idem, après validation fonctionnelle en recette | `outils/promouvoir.sh recette prod` | fusion par un Maintainer ; **synchro manuelle** (`argocd app diff` puis `argocd app sync mediagenda-prod`) ; dernière marche du canary en promotion manuelle ; fenêtres de synchronisation (M20-E29) |

Règles :
- on ne saute pas la recette, on ne redescend pas (le script refuse `dev → prod`) ;
- un digest non signé par la clé MédiSphère n'est pas promu (le script et le pipeline de MR le refusent) ;
- la version de `livraison.yaml` et le digest bougent **ensemble**, dans le même commit.

## Revenir en arrière

**Toujours par Git.** Le retour arrière d'un environnement est un `git revert` de la fusion qui l'a
promu, proposé par MR :

```
git switch -c retour/recette-vX.Y.Z
git revert -m 1 <COMMIT-DE-FUSION>       # -m 1 : on garde le côté « main » de la fusion
git push -u origin retour/recette-vX.Y.Z -o merge_request.create -o merge_request.target=main
```

Après fusion : la recette se resynchronise seule ; la prod se synchronise à la main. Le Rollout traite
le retour comme un changement : il rejoue les étapes et les analyses du canary, **sauf** si la révision
visée est dans sa fenêtre de retour arrière (`spec.rollbackWindow.revisions: 2`, M20-E16) ou si le canary
en cours n'était pas terminé (retour direct à la révision stable) : le retour est alors immédiat.

**Pourquoi pas `argocd app rollback` ?**
- Argo CD le **refuse** tant que la synchronisation automatique est active (« rollback cannot be
  initiated when auto-sync is enabled ») : il faudrait d'abord la couper.
- Sur `mediagenda-dev` et `mediagenda-recette`, la couper ne tient pas : l'ApplicationSet `mediagenda`
  (politique `create-update`) remet `automated` à la réconciliation suivante, et la synchronisation
  automatique réapplique aussitôt `main`.
- Sur `mediagenda-prod` (synchro manuelle), un rollback fonctionne mais laisse l'application
  **OutOfSync** : Git dit une chose, le cluster une autre ; la prochaine synchronisation réapplique Git
  et annule le rollback. Réservé à une urgence absolue, suivi **dans l'heure** d'une MR de revert qui
  remet Git en accord.

**Les données ne reviennent pas en arrière.** Une version qui a appliqué une migration de schéma (Job
`mediagenda-migrate`, M20-E11) la laisse en place : les migrations de MédiAgenda sont **additives**
(nouvelle colonne, nouvel index), la version précédente fonctionne sur le nouveau schéma. Une migration
destructive est interdite dans la même version que le code qui en dépend (voir M20-E20).

## Où lire l'état

```
argocd app list -l medisphere.internal/equipe=mediagenda
argocd app history mediagenda-prod
kubectl argo rollouts get rollout mediagenda -n mediagenda-recette
git log --oneline --first-parent -- overlays/prod      # historique des promotions en prod
```
