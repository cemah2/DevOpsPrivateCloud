# Post-mortem INC-4743 — Mise en production de MédiAgenda suspendue (astreinte du 5 novembre)

> Exemple de post-mortem pour le trio « E37 (identifiants du dépôt) + E40 (analyse du canary) +
> E39 (HPA contre Git) ». Ton post-mortem raconte TES trois pannes, avec TES heures et TES
> empreintes de commits. Format : modèle de l'équipe (modules/00-lab/ressources/M00-E46/).
> Post-mortem sans reproche : on décrit des décisions et des garde-fous manquants, pas des personnes.

| | |
|---|---|
| Gravité | P1 (mise en production bloquée, aucune indisponibilité côté patients) |
| Début / fin | 17 h 40 → 19 h 52 (2 h 12) |
| Rédaction | <MOI>, relu par Nadia Roussel et Karim Benali |
| Statut | Clos ; actions suivies dans PLAT-2143 |

## Résumé

Pendant la mise en production de MédiAgenda, trois défaillances indépendantes se sont cumulées :
Argo CD ne lisait plus le groupe GitLab `mediagenda` (identifiants restaurés d'une ancienne copie),
le canary de recette s'interrompait (analyse de disponibilité visant un chemin inexistant) et les
pods de dev étaient recréés en boucle (HPA ajouté face à `replicas: 1` dans Git). La production n'a
pas été synchronisée ; aucune donnée n'a été touchée.

## Chronologie

| Heure | Événement |
|---|---|
| 17 h 40 | MR de promotion fusionnée ; Julien attend la synchro de prod de 18 h |
| 17 h 46 | Aucune notification reçue ; `argocd app list` : trois applications MédiAgenda `Unknown` |
| 17 h 50 | `argocd app get mediagenda-dev -o json \| jq .status.conditions` : `authentication required` |
| 17 h 58 | `kubectl -n argocd exec deploy/argocd-repo-server -- git ls-remote …` : même refus ; Secret `repo-creds` du groupe mediagenda annoté `restaure-depuis` à 16 h 12 |
| 18 h 05 | `secrets-k8s.sh appliquer argocd` depuis le Vault ; `argocd app get --hard-refresh` : comparaisons rétablies |
| 18 h 10 | Point à Nadia : prod gelée, recette et dev en cours |
| 18 h 20 | Recette : Rollout `Degraded`, `RolloutAborted` ; AnalysisRun `pret` en `Error` (404 sur `/prets`) |
| 18 h 31 | `git log -p overlays/recette` : correctif de Lucas (commit 4c1e9a2b) ; MR de revert !87 fusionnée |
| 18 h 52 | Canary complet en recette, AnalysisRuns `Successful` |
| 19 h 05 | Dev : pods recréés toutes les 2-3 minutes ; `argocd app history` : synchros automatiques sans commit |
| 19 h 14 | `outils/qui-ecrit.sh` : `spec.replicas` disputé entre `argocd-controller` et `kube-controller-manager` (sous-ressource scale) ; HPA ajouté par 7d03e5f1 |
| 19 h 30 | MR !88 : HPA retiré de dev (décision de Julien : pas d'HPA en dev) ; dev stable |
| 19 h 52 | `lab/bin/check 20 43` vert ; feu vert pour la synchro de prod le lendemain 8 h (gel à 16 h) |

## Causes racines

1. **Identifiants** : un Secret géré hors Git (secrets-k8s.sh) a été réécrit à la main depuis une
   copie locale périmée ; rien ne compare l'état des Secrets d'Argo CD avec le Vault.
2. **Analyse** : une modification de l'analyse a été livrée en recette dans le même commit qu'un
   changement de paramètre ; la CI valide la syntaxe, pas le chemin visé.
3. **HPA** : deux écrivains pour `spec.replicas` (Git et le HPA) en dev, où l'Application ne
   déclare pas ce champ comme ignoré.

## Détection

- Aucune alerte n'a signalé les trois Applications `Unknown` : les notifications ne couvrent que
  `on-sync-failed`, `on-health-degraded` et `on-deployed`. Ajouter un déclencheur
  `on-sync-status-unknown`.
- L'abandon du canary de recette a été vu par l'humain, pas par une alerte.

## Ce qui a bien marché

- La prod n'a jamais été synchronisée « pour voir » ; le gel était connu.
- Tous les correctifs sont passés par MR : l'historique Git raconte l'incident.

## Actions

| Action | Responsable | Échéance |
|---|---|---|
| Déclencheur `on-sync-status-unknown` vers astreinte@ | <MOI> | PLAT-2143-1, J+7 |
| Contrôle quotidien Secrets d'Argo CD ↔ Vault (empreintes, sans afficher les valeurs) | Karim | J+14 |
| `verifier-overlay.sh` étendu : modification d'AnalysisTemplate = MR séparée, relue par l'équipe | Julien | J+14 |
| `FailOnSharedResource=true` et règle « pas de HPA sans ignoreDifferences » dans les normes | <MOI> | J+7 |
| Alerte « Rollout aborted » (métriques d'Argo Rollouts, M21) | <MOI> | M21 |
