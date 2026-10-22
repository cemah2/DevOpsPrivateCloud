# Sujet M20-E34 — Une mise en production en temps limité (60 min)

> À ouvrir à T0 seulement. Première commande, avant de lire la suite :
> ```
> admin@adm01:~$ mkdir -p ~/m20/e34 && date -u +%FT%TZ > ~/m20/e34/T0 && cat ~/m20/e34/T0
> ```

## Le changement

> **CHG-2134** — Mise en production de MédiAgenda `<VERSION>` (la version validée en recette : lis-la dans l'overlay `recette` de `mediagenda/deploiement`).
> Demandeur : Julien Petit. Exécutant : toi. Validation : Claire Morel.
> Fenêtre : maintenant, hors fenêtre `deny` (vérifie-le). Retour arrière : `git revert` de la MR de promotion, synchronisation manuelle, ou interruption du canary (`abort`) tant qu'il n'est pas à 100 %.
> Critères d'arrêt : une analyse en échec, une alerte, un `5xx` constaté sur `https://mediagenda.apps.par1.medisphere.internal`.

## Règles

- Tout passe par Git et par Argo CD. Interdit sur `mediagenda-*` : `kubectl apply`, `edit`, `patch`, `scale`, `delete`. Permis : `kubectl get|describe|logs`, `kubectl argo rollouts get|promote|abort|retry`, `argocd app get|diff|sync|history`, les actions d'Argo CD sur le Rollout.
- Documentation permise : tes runbooks et livrables du module, argo-cd.readthedocs.io, argoproj.github.io/argo-rollouts, rollouts-plugin-trafficrouter-gatewayapi.readthedocs.io.
- Une tâche rapporte ses points si **tous** ses contrôles passent. Seuil : 70 points sur 100.
- Note l'heure de fin de chaque tâche dans la feuille de temps (en bas) au fur et à mesure.

## Tâches

| # | Poids | Tâche |
|---|---|---|
| 1 | 10 | **Préparer.** Crée `~/m20/e34/journal.md` : ligne `CHG-2134`, la version à livrer, son digest, l'état de départ de la production (version, digest, `Synced`/`Healthy`), les fenêtres de synchronisation applicables à `mediagenda-prod` et ton plan de retour arrière en trois lignes. |
| 2 | 15 | **Promouvoir.** Ouvre la MR qui porte en production le digest validé en recette (ton outil de promotion du M20-E14), fais-la valider et fusionne-la. La MR cite `CHG-2134`. |
| 3 | 10 | **Vérifier avant de synchroniser.** Sur `main`, l'overlay `prod` référence **le même digest** que l'overlay `recette`. Relève dans le journal le diff que montre Argo CD pour `mediagenda-prod` avant la synchronisation (quels objets changent). |
| 4 | 15 | **Synchroniser.** Synchronise **à la main** `mediagenda-prod` sur la révision fusionnée, avec ton compte nominatif ; l'opération réussit. |
| 5 | 20 | **Conduire le canary.** Suis le Rollout de production jusqu'au bout (marches, analyses, pause finale) et promeus-le quand les critères sont réunis. À la fin : Rollout `Healthy`, entièrement promu, poids de l'HTTPRoute revenus à 100/0. |
| 6 | 15 | **Analyses.** Les analyses de la nouvelle révision (tests de fumée, disponibilité) ont tourné **et** réussi ; aucune analyse en échec depuis T0 en production. |
| 7 | 5 | **Notifier.** Le message d'Argo CD annonçant le déploiement de `mediagenda-prod` est arrivé dans Mailpit (`plateforme@`) après T0. |
| 8 | 10 | **Rendre compte.** `docs/livraison/gitops/tests/mise-en-production-chrono.md` sur `main` de `plateforme/medisphere` : T0, T1, version et digest livrés, chronologie (MR, synchronisation, chaque marche, promotion), incidents, et ta feuille de temps. |

## Vérification

À T1 : `lab/bin/check 20 34` (score par tâche et total). Le check lit `~/m20/e34/T0` : ne le modifie pas.

## Feuille de temps

| Tâche | Heure de fin | Faite / abandonnée | Commentaire (hésitation, documentation consultée) |
|---|---|---|---|
| T0 (ouverture) | | | |
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |
| 6 | | | |
| 7 | | | |
| 8 | | | |
| T1 | | | |
