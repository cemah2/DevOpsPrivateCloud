# Sujet M14-E34 — Examen blanc d'administration (2 h)

> À ouvrir à T0 seulement. Note l'heure maintenant dans la feuille de temps (en bas).

## Règles

- Cluster : `k8s-par1`, depuis `adm01`, avec ton kubeconfig personnel. SSH vers les nœuds permis (`admin`, `sudo`).
- Documentation permise : kubernetes.io, etcd.io, `kubectl explain`, `--help`, tes runbooks. Rien d'autre.
- Sauf mention contraire, tout objet se crée dans l'espace **`wb-examen`**.
- **Image** : partout où le sujet dit `<IMAGE-MEDIAGENDA>`, utilise l'image de MédiAgenda déployée en M14-E07 (`registry.par1.medisphere.internal/medisphere/mediagenda-api:<version>`, avec une version explicite, jamais `latest`).
- Les réponses écrites vont dans **`~/examen-blanc/reponses.txt`** sur `adm01`, une ligne `cle=valeur` par réponse, sans espace autour du `=`.
- Une tâche rapporte ses points si **tous** ses contrôles passent. Seuil : 70 points sur 100.
- Les tâches sont indépendantes, sauf mention contraire. Si une tâche te bloque plus de 10 minutes, passe à la suivante.

## Tâches

| # | Poids | Tâche |
|---|---|---|
| 1 | 4 | Crée l'espace de noms `wb-examen` avec l'étiquette `examen=blanc` ; Pod Security y est appliqué au niveau `baseline` en mode `enforce`. |
| 2 | 6 | Dans `wb-examen` : un ResourceQuota `quota-examen` (au plus 15 pods, 2 CPU et 4 Gio demandés en tout, 6 Gio de limites mémoire en tout) et un LimitRange `limites-examen` qui donne à chaque conteneur, par défaut, une demande de `100m` CPU et `128Mi` de mémoire et une limite mémoire de `256Mi`. |
| 3 | 10 | Un ConfigMap `api-examen-config` avec `MEDIAGENDA_DB_URL=postgresql://examen@base.wb-examen.svc:5432/examen`, `MEDIAGENDA_VALKEY_URL=redis://cache.wb-examen.svc:6379/0` et `MEDIAGENDA_LOG_LEVEL=INFO`. Un Deployment `api-examen` de **3** réplicas, étiquette `app=api-examen`, image `<IMAGE-MEDIAGENDA>`, toutes les variables du ConfigMap injectées dans l'environnement, sondes de vivacité **et** de disponibilité sur `GET /sante` port 8000 (il n'y a pas de base dans cet exercice : `/pret` répondrait 503), demande `100m` CPU / `128Mi`, limite mémoire `256Mi`. Les 3 réplicas sont prêts. |
| 4 | 6 | Les réplicas de `api-examen` sont répartis entre les zones (`topology.kubernetes.io/zone`) avec un écart maximal de 1 ; une réplique qui ne pourrait pas respecter la règle **n'est pas** ordonnancée ; seuls comptent les nœuds sur lesquels ces pods **peuvent** réellement aller (pense aux taints). Les 3 réplicas restent prêts. |
| 5 | 5 | Un Service `api-examen` de type `ClusterIP`, port 80 vers le port 8000 des pods de `api-examen` ; il a 3 points d'accès prêts. |
| 6 | 5 | Une PodDisruptionBudget `api-examen` qui garantit au moins 2 réplicas disponibles pendant un drainage. |
| 7 | 8 | Un compte de service `lecteur-examen`, un Role `lecture-pods` qui permet **seulement** `get`, `list` et `watch` sur les pods et leurs journaux (`pods/log`), et un RoleBinding `lecteur-examen` qui l'attribue au compte de service. |
| 8 | 6 | Un CronJob `purge-examen` : toutes les 15 minutes, **heure de Paris**, jamais deux exécutions simultanées, 2 réussites et 1 échec conservés ; il lance `<IMAGE-MEDIAGENDA>` avec la commande `python -c "print('purge')"` et ne redémarre pas un conteneur en échec. |
| 9 | 10 | Applique le manifeste fourni [`rdv-examen.yaml`](rdv-examen.yaml) (remplace d'abord `<IMAGE-MEDIAGENDA>`). Le Deployment `rdv-examen` ne fonctionne pas et son Service ne sert rien : répare-les (en modifiant les objets, pas leur nom) jusqu'à ce que les 2 réplicas soient prêts et que le Service `rdv-examen` ait 2 points d'accès. |
| 10 | 6 | Pose l'étiquette `examen.medisphere.internal/frontal=oui` sur `k8s-w01`. Crée un Deployment `frontal-examen` d'un réplica (image `<IMAGE-MEDIAGENDA>`, même ConfigMap qu'en tâche 3) dont le pod **doit** tourner sur un nœud portant cette étiquette (affinité de nœud obligatoire, pas `nodeSelector`). Le pod tourne sur `k8s-w01`. |
| 11 | 8 | Pose sur `k8s-w03` le taint `examen=maintenance:NoSchedule`. Crée un pod `outil-examen` (image `<IMAGE-MEDIAGENDA>`, commande `sleep 7200`) qui tourne **sur `k8s-w03`**, sans utiliser `spec.nodeName`. |
| 12 | 10 | Sur `k8s-cp01`, prends un instantané etcd dans `/var/backups/etcd/examen-blanc.db` (le fichier n'existe pas avant T0) et vérifie-le. Écris sa révision dans `reponses.txt` : `revision_instantane=<révision>`. |
| 13 | 8 | Écris dans `reponses.txt` : `version_etcd=<version d'etcd du cluster, ex. 3.6.8>`, `leader_etcd=<nom du membre etcd leader au moment où tu réponds>`, `cidr_pods_k8s-w02=<plage d'adresses de pods attribuée par Cilium à k8s-w02>`. |
| 14 | 8 | Crée une PriorityClass `examen-haute` (valeur `100000`, pas par défaut, **sans** préemption) et fais-la utiliser par les pods de `api-examen` (les 3 réplicas restent prêts). |

## Vérification

À T1, depuis `adm01` : `lab/bin/check 14 34` (score par tâche et total). **Avant** le nettoyage.

## Nettoyage (après la vérification)

```
admin@adm01:~$ kubectl delete namespace wb-examen
admin@adm01:~$ kubectl delete priorityclass examen-haute
admin@adm01:~$ kubectl label node k8s-w01 examen.medisphere.internal/frontal-
admin@adm01:~$ kubectl taint node k8s-w03 examen=maintenance:NoSchedule-
admin@adm01:~$ ssh k8s-cp01 sudo rm -f /var/backups/etcd/examen-blanc.db
```

## Feuille de temps

| Tâche | Heure de fin | Faite / abandonnée | Commentaire (hésitation, doc consultée) |
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
| 9 | | | |
| 10 | | | |
| 11 | | | |
| 12 | | | |
| 13 | | | |
| 14 | | | |
| T1 (vérification) | | | |
