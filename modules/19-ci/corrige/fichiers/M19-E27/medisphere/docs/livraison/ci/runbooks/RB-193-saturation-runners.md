# RB-193 — Saturation des runners

| | |
|---|---|
| Rédigé | M19-E27 (PLAT-2027) |
| Symptôme | jobs « pending » qui démarrent tard (attente p95 > 60 s), pods de job `Pending`, jobs en échec « timed out waiting for pod to start » |
| Voir aussi | RB-190 (un pipeline reste en attente : runner, étiquettes, protection), `capacite-runners.md` |

## 1. Saturation ou panne ?

Un job **qui n'est pris par aucun runner** (pas de pod créé) relève de RB-190 (étiquettes, runner en pause, référence non protégée pour `protege`). Ici : les jobs sont pris, mais tard, ou leurs pods attendent.

```
admin@adm01:~$ kubectl -n ci-jobs get pods --field-selector=status.phase=Pending
admin@adm01:~$ kubectl -n ci-jobs describe resourcequota
admin@adm01:~$ kubectl top nodes
admin@adm01:~$ kubectl -n gitlab-runner get pods -o wide
admin@adm01:~$ bin/ci-mesurer-pipeline.sh mediagenda/api <PIPELINE>
```

## 2. Arbre de décision

| Constat | Cause probable | Geste |
|---|---|---|
| Un seul gestionnaire en ligne (`/runners/:id/managers`) | réplica en panne ou nœud drainé | rétablir le réplica ; vérifier le PDB et la répartition |
| Gestionnaires à `concurrent` jobs, pods tous `Running` | plafond atteint | normal en pic ; si chronique, §3 |
| Pods `Pending`, événement `exceeded quota` | quota de `ci-jobs` atteint | ne pas augmenter `concurrent` ; revoir les demandes des jobs gourmands (surcharges `KUBERNETES_*`) ou le quota (§3) |
| Pods `Pending`, `Insufficient memory/cpu` | nœuds pleins | jobs préemptés par les applications (normal) ou capacité du cluster : §3 |
| Pods `Pending` après préemption (événement `Preempted`) | applications prioritaires | normal ; relancer les jobs |
| Constructions lentes, autres jobs normaux | buildkitd saturé | étaler, cache BuildKit (E23) |

## 3. Ajouter de la capacité (dans cet ordre)

1. Réduire la demande : `interruptible` + `auto_cancel` (E06), `needs` et caches (E23), jobs inutiles en MR.
2. Ajuster `request_concurrency` (si les gestionnaires ont des places libres mais prennent les jobs un à un).
3. Augmenter `concurrent`/`limit` **avec** le quota, et seulement si les nœuds ont la mémoire (calcul de `capacite-runners.md` §2 refait).
4. Ajouter un travailleur ou de la mémoire (OpenTofu `envs/k8s`) : décision de Claire Morel.
5. Refuser : un pic ponctuel (lundi 9 h) ne justifie pas de dimensionner pour lui.

## 4. Maintenance d'un nœud sans perdre de jobs

```
admin@adm01:~$ kubectl cordon k8s-w02
admin@adm01:~$ kubectl -n ci-jobs get pods -o wide --field-selector spec.nodeName=k8s-w02   # attendre qu'il n'y en ait plus
admin@adm01:~$ kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data
```
Le gestionnaire qui tournait sur le nœud est déplacé par le drainage (PDB : un à la fois) ; l'autre continue.
