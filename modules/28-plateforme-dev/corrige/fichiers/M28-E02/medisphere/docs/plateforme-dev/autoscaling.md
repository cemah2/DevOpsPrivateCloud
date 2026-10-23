# Autoscaling des applications

> Plateforme développeurs — M28-E02 (DEV-2902), complété en M28-E03 (PLAT-2903). Responsable : équipe Plateforme. Relu par : Karim Benali, Julien Petit.

## Principes

1. **Un seul pilote par champ.** L'HPA (ou le ScaledObject de KEDA, qui crée un HPA) possède `spec.replicas` de sa cible. Git ne le déclare plus ; Argo CD l'ignore (`ignoreDifferences` + `RespectIgnoreDifferences`).
2. **Le pourcentage CPU se calcule sur les `requests`.** Des `requests` fausses donnent un autoscaling faux. Elles sont mesurées, écrites ici et revues avec les recommandations du VPA (`recommandations-ressources.md`).
3. **Monter vite, descendre lentement.** Une montée trop lente coûte des erreurs ; une descente trop rapide coûte des oscillations (chaque nouveau pod paie son démarrage).
4. **Pas d'essai de charge en production.**

## MédiAgenda — HPA `mediagenda` (CPU)

| | Recette | Production |
|---|---|---|
| Cible | Rollout `mediagenda` (`argoproj.io/v1alpha1`) | idem |
| Bornes | 2 → 4 | 3 → 6 |
| Métrique | CPU, 70 % des `requests` | idem |
| Montée | immédiate ; au plus max(+100 %, +2 pods) par minute | idem |
| Descente | fenêtre de stabilisation 300 s ; au plus 1 pod / 2 min | idem |
| Déclaré dans | `mediagenda/deploiement`, `components/autoscaling` | idem + correctif de l'overlay `prod` |

### Mesures et `requests`

> Ordres de grandeur du corrigé : **remplace-les par tes mesures**.

| Mesure (pod de recette) | CPU | Mémoire |
|---|---|---|
| Au repos | ≈ 15 m | ≈ 140 Mi |
| Sous `charge.sh` (≈ 60 req/s sur 2 pods) | ≈ 180 m | ≈ 170 Mi (pic 210 Mi) |
| `requests` retenues | **200 m** | **192 Mi** |
| Limite | aucune (CPU) | **384 Mi** |

Requêtes PromQL utilisées : `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="mediagenda-recette", container="api"}[2m]))` et `max by (pod) (container_memory_working_set_bytes{namespace="mediagenda-recette", container="api"})`.

### Transition sans à-coup (ordre des MR)

1. **MR `plateforme/gitops`** : `ignoreDifferences` sur `/spec/replicas` du Rollout (recette, prod). Rien ne change dans le cluster.
2. **MR `mediagenda/deploiement`** (recette, puis prod) : HPA **et** retrait de `replicas` dans la même MR.

Pourquoi : tant que Git déclarait `replicas`, le gestionnaire de champs `argocd-controller` (application côté serveur) possédait `spec.replicas`. Si Git cesse de le déclarer **avant** qu'un autre gestionnaire ne le possède, l'application côté serveur supprime le champ et le Rollout retombe à sa valeur par défaut (1 pod) le temps que l'HPA réagisse. Avec l'`ignoreDifferences` posé d'abord, puis l'HPA dans la même synchronisation : l'HPA écrit `spec.replicas` par la sous-ressource `scale` (gestionnaire `kube-controller-manager`, opération `Update`), ce qui lui transfère la propriété du champ. Contrôle : `kubectl -n mediagenda-recette get rollout mediagenda -o yaml --show-managed-fields | yq '.metadata.managedFields[] | select(.fieldsV1["f:spec"]["f:replicas"]) | .manager'` → seul `kube-controller-manager` apparaît. *(Comportement à vérifier sur ton lab : relève le nombre de pods pendant la synchronisation.)*

### Essai de charge (recette)

| Relevé | Valeur |
|---|---|
| Délai avant la première montée | ≈ 30-45 s (fenêtre de metrics-server + période de l'HPA) |
| Nombre maximal de pods | 4 (borne) |
| Retour au minimum après la fin de la charge | ≈ 5 min (stabilisation) + 2 min par pod retiré |
| Application `mediagenda-recette` pendant l'essai | `Synced` |

## Supervision

Panneau « Réplicas de l'API (HPA) » du tableau de bord MédiAgenda : désirés, actuels, maximum (kube-state-metrics). Une valeur désirée collée au maximum pendant plus de 15 min signale un sous-dimensionnement (alerte au palier 3).
