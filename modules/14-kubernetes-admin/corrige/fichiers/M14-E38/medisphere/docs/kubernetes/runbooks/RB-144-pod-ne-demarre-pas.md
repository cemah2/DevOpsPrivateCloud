# RB-144 — Un pod ne démarre pas

| | |
|---|---|
| Cluster | `k8s-par1` (Kubernetes 1.36, containerd 2.3, Harbor `registry.par1.medisphere.internal`) |
| Rédigé | M14-E36 (Pending), M14-E37 (ImagePullBackOff), M14-E38 (CrashLoopBackOff) |
| Escalade | équipe Plateforme (astreinte), puis l'équipe propriétaire de l'application |

## 0. Où en est le pod ?

```
admin@adm01:~$ kubectl -n <ESPACE> get deploy,rs,pods -o wide
admin@adm01:~$ kubectl -n <ESPACE> get events --sort-by=.lastTimestamp | tail -n 20
admin@adm01:~$ kubectl -n <ESPACE> describe pod <POD>
```

| Ce que je vois | Étage | Section |
|---|---|---|
| le pod n'existe pas, le ReplicaSet a `DESIRED` > `CURRENT` | admission | § Pending (quota, admission) |
| `Pending`, `PodScheduled=False`, `FailedScheduling` | ordonnanceur | § Pending |
| `ErrImagePull`, `ImagePullBackOff` | kubelet → runtime → registre | § ImagePullBackOff |
| `ContainerCreating` qui dure | runtime, réseau, volumes | événements `FailedCreatePodSandBox`, `FailedMount` |
| `CrashLoopBackOff`, `RESTARTS` qui monte | application, sondes, ressources | § CrashLoopBackOff |

## Pending

| Message | Cause | Confirmation | Correctif |
|---|---|---|---|
| `exceeded quota: <quota>, requested: … used: … limited: …` (événement du ReplicaSet) | quota de l'espace atteint | `kubectl describe resourcequota -n <ESPACE>` | valeur du code (`plateforme/k8s/espaces/`), marge ≥ `maxSurge` |
| `untolerated taint {clé: valeur}` | taint sur les nœuds | `kubectl get nodes -o custom-columns=NOM:.metadata.name,TAINTS:.spec.taints[*].key` | retirer la taint posée hors procédure ; maintenance = `cordon`/`drain` |
| `Insufficient memory` / `Insufficient cpu` | demandes > allouable | `kubectl describe node` (Allocatable, Allocated resources) | `rollout undo`, demandes réalistes, `LimitRange` avec `max` |
| `didn't match Pod's node affinity/selector` | affinité ou `nodeSelector` impossible | `kubectl get nodes -L topology.kubernetes.io/zone` | `rollout undo` ; répartition par `topologySpreadConstraints` |
| `node(s) were unschedulable` | nœuds cordonnés | `kubectl get nodes` (`SchedulingDisabled`) | `uncordon` si la maintenance est finie |

Le message de l'ordonnanceur compte les nœuds par raison : la somme fait le nombre de nœuds (6).

## ImagePullBackOff

| Message (extrait) | Cause | Confirmation |
|---|---|---|
| `failed to fetch oauth token … 401 Unauthorized` | identifiants refusés (jeton du robot) | `sudo crictl pull --creds …` sur le nœud ; journal de Harbor |
| `Unable to retrieve some image pull secrets (…)` puis `pull access denied` | Secret de tirage absent ou mal nommé | `kubectl get pod -o jsonpath='{.spec.imagePullSecrets}'`, `kubectl get secret` |
| `<image>: not found` sur une image `docker.io/…` | `hosts.toml` du registre faux | `cat /etc/containerd/certs.d/docker.io/hosts.toml`, `journalctl -u containerd` |
| `… @sha256:…: not found` | digest inexistant | digest lu dans Harbor (API, `crane digest`) |
| `x509: certificate signed by unknown authority` | CA MédiSphère absente du nœud | `openssl s_client -connect registry.par1.medisphere.internal:443` sur le nœud |
| `i/o timeout`, `connection refused` | réseau, bordure, Harbor arrêté | `curl -sI https://registry.par1.medisphere.internal/v2/` depuis le nœud |

Règles : ne jamais afficher le jeton du robot (`read -rs`) ; recréer un Secret de tirage depuis Vault, jamais depuis une sauvegarde ; ne pas « contourner » par `imagePullPolicy: IfNotPresent` ni en tirant directement de Docker Hub.

## CrashLoopBackOff

```
admin@adm01:~$ kubectl -n <ESPACE> get pod <POD> -o jsonpath='{.status.containerStatuses[0].lastState}' | jq .
admin@adm01:~$ kubectl -n <ESPACE> logs <POD> --previous
admin@adm01:~$ kubectl -n <ESPACE> rollout history deploy/<NOM> --revision=<N>
```

| Ce que je vois | Ce que ça veut dire | Commande suivante |
|---|---|---|
| `Error`, code 1 ou 2, journaux explicites | le processus sort de lui-même (configuration) | lire le message ; comparer au contrat de l'application (README) |
| `Unhealthy … Liveness probe failed`, `Killing` | le kubelet tue un conteneur peut-être sain | sonde contre le contrat (chemin, port, délais, `startupProbe`) |
| `OOMKilled`, code 137 | le noyau a tué : limite de mémoire | usage réel mesuré (`kubectl top pod`, M14-E20) contre `limits.memory` |
| `StartError`, code 128, `executable file not found` | le conteneur n'a jamais démarré | `command`/`args` contre l'`ENTRYPOINT` de l'image |
| code 137 sans `OOMKilled` | tué par SIGKILL (arrêt trop long, sonde) | `terminationGracePeriodSeconds`, événements |

Correctif d'urgence : `kubectl -n <ESPACE> rollout undo deploy/<NOM>` si la révision précédente est saine ; correctif définitif dans le dépôt de l'équipe.

## Prévention

- CI des équipes : déploiement dans `mediagenda-dev` avec `kubectl rollout status --timeout=…` (M19), retour arrière automatique (M17, M20).
- Quotas, LimitRanges et politiques d'admission par le code, avec marge pour les mises à jour progressives.
- Alertes (module 21) : pods `Pending` > 5 min, `ImagePullBackOff`, redémarrages en hausse.
