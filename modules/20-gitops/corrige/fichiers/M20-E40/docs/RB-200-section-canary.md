## Le canary ne progresse plus (Argo Rollouts)

> Section ajoutée à RB-200 après INC-4740 (M20-E40). Un canary bloqué ne casse pas la production :
> la version stable sert le trafic. Il bloque la livraison. On ne le débloque jamais en sautant
> les analyses.

1. **Photographier** : `outils/canary-etat.sh <espace>` (Rollout, AnalysisRuns et leurs mesures,
   poids réels de la HTTPRoute, contrôleur et greffon, synchronisations d'Argo CD).
2. **Classer** :
   | Constat | Cause probable | Correctif |
   |---|---|---|
   | `Degraded`, `RolloutAborted`, analyse en `Error` (code HTTP, délai) | la mesure est impossible (URL, réseau des analyses, service canary) | corriger la mesure par MR ; une analyse qu'on ne sait pas faire n'est pas une analyse réussie |
   | `Degraded`, analyse en `Failed` | la nouvelle version est mauvaise | **c'est le système qui marche** : corriger la version, nouvelle promotion |
   | contrôleur en `CrashLoopBackOff`, journaux « plugin » | configuration du greffon (`trafficRouterPlugins`) | revert de la configuration ; redémarrage du contrôleur ; tester tout changement de greffon par un redémarrage volontaire |
   | synchronisations automatiques en boucle pendant le canary, poids qui oscillent | Argo CD ne laisse plus les poids au greffon | `ignoreDifferences` des poids de la HTTPRoute + `RespectIgnoreDifferences=true` |
   | `Paused` sans condition d'étape (`spec.paused: true`) | pause manuelle | demander pourquoi, puis `kubectl argo rollouts resume` |
3. **Ne jamais** `kubectl argo rollouts promote --full` un canary dont l'analyse échoue ; ne jamais
   modifier les poids de la HTTPRoute à la main.
4. **Vérifier** par un canary complet : toutes les étapes, analyses `Successful`, poids revenus à
   100 % sur le stable, Rollout `Healthy`.
