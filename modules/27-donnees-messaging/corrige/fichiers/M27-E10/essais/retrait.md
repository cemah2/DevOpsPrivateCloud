# Plan de retrait de l'essai Kafka (modèle) — `~/m27/e10/retrait.md`

## Ce qui existe (relevé avant d'agir)

```
admin@adm01:~$ kubectl -n kafka-essai get all,pvc,secrets,networkpolicies,pdb,kafka,kafkanodepool,kafkatopic,kafkauser,strimzipodset
admin@adm01:~$ kubectl get crd -o name | grep strimzi.io                         # 10 CRD (kafka.strimzi.io, core.strimzi.io)
admin@adm01:~$ kubectl get clusterroles,clusterrolebindings -o name | grep -i strimzi
admin@adm01:~$ kubectl get pv | grep kafka-essai
admin@adm01:~$ kubectl get kafkatopic -n kafka-essai -o jsonpath='{.items[*].metadata.finalizers}'
```

## Pourquoi un ordre

- Les `KafkaTopic` portent un *finalizer* de l'opérateur de *topics* (il supprime le *topic* dans Kafka avant de libérer l'objet). Si l'opérateur d'entité disparaît d'abord (la `Kafka` supprimée en même temps), leur suppression reste bloquée.
- Les PVC des nœuds survivent à la grappe (`deleteClaim: false`) : à supprimer explicitement, **après** l'arrêt des pods.
- Les CRD sont suivies par l'Application (livrées par le chart, sans annotation de conservation) : supprimer l'Application en cascade les supprime, et avec elles tout objet restant de ces types.

## Étapes

1. **MR `plateforme/donnees`** : retirer `medinotif-kafka.yaml`, `topics.yaml` et `utilisateurs.yaml` de `kafka-essai/`. Synchronisation (élagage) ; attendre `kubectl -n kafka-essai get kafkatopic,kafkauser` → aucun objet.
2. **MR `plateforme/donnees`** : supprimer le dossier `kafka-essai/` (Kafka et pool). L'opérateur arrête les pods ; attendre qu'il n'en reste que l'opérateur.
3. Supprimer les PVC (seul geste à la main, sur un espace d'essai) : `kubectl -n kafka-essai delete pvc -l strimzi.io/cluster=kafka-essai` ; vérifier que les PV (`Delete`) disparaissent et que les images RBD sont libérées (`rbd ls` du pool, M16).
4. **MR `plateforme/gitops`** : supprimer `plateforme/kafka-essai.yaml` et `valeurs/strimzi/` ; retirer `kafka-essai` des destinations de l'AppProject `plateforme`. L'Application est supprimée **en cascade** (finaliseur `resources-finalizer.argocd.argoproj.io` : vérifie qu'il est posé, sinon supprime-la avec `argocd app delete --cascade`) : opérateur, ClusterRoles, liaisons, CRD.
5. **MR `plateforme/k8s`** : supprimer `espaces/kafka-essai/` ; `task appliquer` (ou la suppression de l'espace, selon la façon dont `task appliquer` élague).
6. **MR `plateforme/charts-miroir`** : retirer l'entrée `strimzi-kafka-operator`. Images du cache Harbor : laissées à la purge habituelle du cache (rien ne les tire plus).
7. **`wb-checks-services`** : la règle de lecture de `kafka.strimzi.io` peut rester (un groupe absent ne gêne pas) ; la retirer si l'on veut un rôle sans règle morte.
8. **Documentation** : `kafka-essai.md` (retrait effectif, date), `comparatif-messagerie.md` (décision), matrice des flux.
9. **Worker** : MR de revert du backend Kafka sur `medinotif/worker` (décision du comparatif).

## Vérification finale

```
admin@adm01:~$ kubectl get ns kafka-essai                                  # NotFound
admin@adm01:~$ kubectl get crd -o name | grep -c strimzi.io                # 0
admin@adm01:~$ kubectl get pv -o json | jq -r '.items[] | select(.spec.claimRef.namespace == "kafka-essai") | .metadata.name'   # rien
admin@adm01:~$ kubectl get clusterroles -o name | grep -ci strimzi         # 0
admin@adm01:~$ kubectl -n argocd get application kafka-essai               # NotFound
admin@adm01:~$ lab/bin/check 27 10
```
