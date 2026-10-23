# RB-286 — Pods qui oscillent ou redémarrent sous l'autoscaling

> Pods remplacés en boucle, effectif qui monte et descend sans charge, OOMKilled après une MR d'autoscaling. Rédigé en M28-E20. Propriétaire : équipe Plateforme.

## Distinguer
| Signe | Lecture |
|---|---|
| `RESTARTS` qui augmente, même pod | conteneur tué : `kubectl get pod <p> -o jsonpath='{.status.containerStatuses[*].lastState.terminated.reason}'` (`OOMKilled` → limites) |
| pods nouveaux, noms différents | quelqu'un **supprime** ou **réduit** : événements `EvictedByVPA` (updater du VPA), `ScalingReplicaSet` (contrôleur), historique d'Argo CD |

## Qui écrit ?
1. `kubectl -n <ns> get <charge> <nom> --show-managed-fields -o yaml` : propriétaire de `spec.replicas` (`argocd-controller` = Git ; HPA par la sous-ressource `scale`).
2. `kubectl -n <ns> get vpa -o custom-columns=NOM:.metadata.name,MODE:.spec.updatePolicy.updateMode` : tout autre mode que `Off` hors `wb-essais` est une anomalie.
3. `requests` effectives d'un pod contre celles du gabarit : écart = contrôleur d'admission du VPA.
4. `argocd app history <app>` et `git log -p` des overlays et de `plateforme/gitops/applications/`.

## Règles (et pourquoi)
- Jamais VPA actif + HPA sur le CPU ou la mémoire de la même charge : chacun déplace la cible de l'autre.
- Jamais `replicas` dans Git pour une charge pilotée par un HPA ou KEDA, et `ignoreDifferences` + `RespectIgnoreDifferences=true` sur `/spec/replicas` dans l'Application.
- Un VPA ne se borne pas « pour économiser » : en `RequestsAndLimits`, la limite suit la request.

## Correctif
Revert par MR ; puis renouveler les pods créés pendant l'incident (`kubectl argo rollouts restart`, `kubectl rollout restart`) pour qu'ils retrouvent les requests du gabarit. Vérifier 15 min sans redémarrage.

## Prévention
Revue de MR : toute modification d'un `VerticalPodAutoscaler`, d'un `ignoreDifferences` ou d'un `replicas` dans une charge autoscalée exige l'approbation de la Plateforme (`CODEOWNERS`).
