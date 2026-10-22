# Compte rendu : reconstruction d'Argo CD (M20-E28)

| | |
|---|---|
| Date | <DATE> |
| Opérateur | <MOI> |
| Runbook | RB-201 |
| Export utilisé | `argocd-sauvegardes/quotidien/<OBJET>.yaml.gpg` (<HEURE>) |
| Instantané etcd / sauvegarde Velero | `<OBJET-ETCD>` / `avant-rb201-<DATE>` |

## Avant

Relevé par :
```
admin@adm01:~$ for ns in mediagenda-dev mediagenda-recette mediagenda-prod medidoc-dev medidoc-recette; do
>   kubectl --context k8s-par1 -n "$ns" get deploy,statefulset,pods -o json \
>     | jq -r --arg ns "$ns" '.items[] | [$ns, .kind, .metadata.name, .metadata.uid, .metadata.creationTimestamp] | @tsv'
> done > /dev/shm/avant.tsv
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m20/lyo-k3s01.kubeconfig -n agence get deploy,pods -o json \
>   | jq -r '.items[] | ["agence", .kind, .metadata.name, .metadata.uid, .metadata.creationTimestamp] | @tsv' >> /dev/shm/avant.tsv
```

| Espace | Objet | UID (8 premiers) | Création |
|---|---|---|---|
| mediagenda-prod | Deployment/mediagenda | <…> | <…> |
| mediagenda-prod | Pod/mediagenda-db-1 | <…> | <…> |
| … | | | |

Applications avec finaliseur avant 4.2 : <liste> (attendu : `racine`, `labo`, `argo-rollouts` selon tes choix d'E04-E15 ; aucune Application générée par un ApplicationSet).

## Chronométrage

| Étape (RB-201) | Début | Fin | Durée | Remarque |
|---|---|---|---|---|
| 3 préalables | | | | |
| 4.1 arrêt des contrôleurs | | | | |
| 4.2 finaliseurs | | | | |
| 4.3-4.4 ApplicationSets, Applications, projets | | | | |
| 4.5 release, CRD, espace | | | | |
| 5.1-5.2 espace, politiques, Helmfile | | | | |
| 5.3-5.4 Secrets, restauration d'`argocd-secret` | | | | |
| 5.5 racine → toutes `Synced` | | | | |
| **RTO** (4.1 → dernier `Synced`) | | | | |

## Après

```
admin@adm01:~$ ... même relevé > /dev/shm/apres.tsv ; diff <(cut -f1-4 /dev/shm/avant.tsv | sort) <(cut -f1-4 /dev/shm/apres.tsv | sort)
```
Résultat attendu : aucune différence (aucun objet recréé). Obtenu : <…>.

| Vérification | Résultat |
|---|---|
| `argocd app list` : toutes `Synced`/`Healthy` | |
| Ancien jeton `ci-lecture` accepté (`lab/bin/check 20 28`) | |
| `lyo-k3s01` `Successful` | |
| Webhook : événement 200 au *push* suivant | |
| Sauvegarde : Job manuel réussi, objet dans `argocd-sauvegardes` | |

## Écarts et suites

- <ex. Application `labo` `OutOfSync` après 5.5 : annotation de suivi … ; corrigé par …>
- <ex. RB-201 §4.4 : les AppProjects portaient un finaliseur, ajouté au runbook>
